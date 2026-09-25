#!/usr/bin/env bash
#
# build-release.sh — 构建 DSH Desktop 的 Linux x86_64 发行产物
#
# 产出：
#   dist-release/dsh-desktop-<ver>-linux-x64.tar.zst      ← 上传到 GitHub Releases 的那个文件
#   dist-release/dsh-desktop-<ver>-linux-x64.tar.zst.sha256
#
# 压缩包内结构（AUR 的 dsh-desktop-bin/PKGBUILD 按这个结构解包）：
#   dsh-desktop-<ver>-linux-x64/
#     app/                     electron-builder 的 linux-unpacked 全部内容
#     dsh-desktop.desktop
#     LICENSE                  上游 MIT 许可证（再分发时必须附带）
#     icons/{16..512}x{...}.png
#
# 用法：
#   ./build-release.sh                 # 构建当前 VERSION
#   VERSION=0.9.3 ./build-release.sh   # 指定版本
#   KEEP_WORK=1 ./build-release.sh     # 保留 .build/ 便于排查
#
set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-dataelement/dsh-desktop}"
VERSION="${VERSION:-0.9.2}"
WORKDIR="${WORKDIR:-$PWD/.build}"
OUTDIR="${OUTDIR:-$PWD/dist-release}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# ---------------------------------------------------------------------------
# 构建缓存。四个变量由四个不同层次各自读取，缺一个都会在受限环境下失败：
#   npm_config_cache         npm
#   electron_config_cache    electron 包的 install.js（@electron/get）
#   XDG_CACHE_HOME           @electron/get 自身的默认缓存根（env-paths）
#   ELECTRON_BUILDER_CACHE   electron-builder 打 linux-unpacked 时再取一次
# ---------------------------------------------------------------------------
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$WORKDIR/.cache}"
export npm_config_cache="${npm_config_cache:-$WORKDIR/.cache/npm}"
export electron_config_cache="${electron_config_cache:-$XDG_CACHE_HOME/electron}"
export ELECTRON_BUILDER_CACHE="${ELECTRON_BUILDER_CACHE:-$XDG_CACHE_HOME/electron-builder}"
export npm_config_audit=false
export npm_config_fund=false

PKG="dsh-desktop-$VERSION-linux-x64"
SRC="$WORKDIR/src"
TARBALL="$OUTDIR/$PKG.tar.zst"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m错误:\033[0m %s\n' "$*" >&2; exit 1; }

for c in curl tar zstd npm node; do
  command -v "$c" >/dev/null 2>&1 || die "缺少命令：$c"
done

mkdir -p "$WORKDIR" "$OUTDIR"

# --- 1. 取上游源码（tag 归档，比 git clone 小 30 倍且可校验）----------------
ARCHIVE="$WORKDIR/upstream-v$VERSION.tar.gz"
if [[ ! -f "$ARCHIVE" ]]; then
  log "下载上游 v$VERSION 源码归档"
  curl -fL --retry 3 --connect-timeout 20 \
    -o "$ARCHIVE.part" \
    "https://github.com/$UPSTREAM_REPO/archive/refs/tags/v$VERSION.tar.gz"
  mv "$ARCHIVE.part" "$ARCHIVE"
fi
log "上游归档 sha256: $(sha256sum "$ARCHIVE" | cut -d' ' -f1)"

rm -rf "$SRC"
mkdir -p "$SRC"
tar -xzf "$ARCHIVE" -C "$SRC" --strip-components=1
[[ -f "$SRC/package.json" ]] || die "解包后找不到 package.json"

# --- 2. npm ci -------------------------------------------------------------
# npm 12 起引入两道默认门禁，@ 见 AUR-上传指南.md：
#   --allow-remote=all              lockfile 的 resolved 指向 npmmirror，
#                                   与默认 registry 主机名不同会被判定为 remote 而拒绝
#   --dangerously-allow-all-scripts 依赖的 install 脚本默认不执行，
#                                   而 Electron 与随包 Node 运行时靠它下载
# 这两个开关在 npm 10/11 上只是未使用的配置项，不会报错。
log "npm ci（约 1GB 下载，首次较慢）"
( cd "$SRC" && npm ci --allow-remote=all --dangerously-allow-all-scripts )

# --- 3. 打包 ---------------------------------------------------------------
log "electron-vite build + electron-builder --dir"
( cd "$SRC" && npm run package:dir )

[[ -x "$SRC/dist/linux-unpacked/dsh-desktop" ]] \
  || die "未找到 dist/linux-unpacked/dsh-desktop"

# --- 4. 组装发布树 ---------------------------------------------------------
log "组装 $PKG/"
STAGE="$WORKDIR/$PKG"
rm -rf "$STAGE"
mkdir -p "$STAGE/icons"

cp -r "$SRC/dist/linux-unpacked" "$STAGE/app"
cp "$SRC/LICENSE" "$STAGE/LICENSE"
cp "$SRC/build/app-icon.png" "$WORKDIR/app-icon.png"

if command -v magick >/dev/null 2>&1; then MAGICK=magick
elif command -v convert >/dev/null 2>&1; then MAGICK=convert
else die "需要 imagemagick（magick 或 convert）来生成图标"; fi
for s in 16 32 48 64 128 256 512; do
  "$MAGICK" "$SRC/build/app-icon.png" -resize "${s}x${s}" "$STAGE/icons/${s}x${s}.png"
done

# .desktop：由上游仓库的图标名 + 固定路径生成
cat > "$STAGE/dsh-desktop.desktop" <<'EOF'
[Desktop Entry]
Name=DSH Desktop
Name[zh_CN]=DSH 桌面版
Comment=A cross-platform desktop shell for DeepSeek Harness
Comment[zh_CN]=DeepSeek Harness 的跨平台桌面客户端
Exec=/opt/dsh-desktop/dsh-desktop %U
Terminal=false
Type=Application
Icon=dsh-desktop
StartupWMClass=dsh-desktop
Categories=Development;
Keywords=DSH;DeepSeek;Harness;AI;Agent;
EOF

# 自检：结构与体积
[[ -x "$STAGE/app/dsh-desktop" ]] || die "app/dsh-desktop 不可执行"
[[ -f "$STAGE/app/resources/app/node_modules/node/bin/node" ]] \
  || die "缺少随包 Node 运行时"
log "发布树大小: $(du -sh "$STAGE" | cut -f1)"

# --- 5. 压缩 + 校验和 ------------------------------------------------------
log "压缩成 tar.zst"
rm -f "$TARBALL"
( cd "$WORKDIR" && tar --zstd -cf "$TARBALL" "$PKG" )

log "计算校验和"
( cd "$OUTDIR" && sha256sum "$(basename "$TARBALL")" > "$(basename "$TARBALL").sha256" )

if [[ "${KEEP_WORK:-0}" != "1" ]]; then
  rm -rf "$STAGE"
fi

cat <<EOF

完成。

  产物 : $TARBALL  ($(du -h "$TARBALL" | cut -f1))
  校验 : $(cat "$TARBALL.sha256")

下一步：
  1. 建 GitHub Release，tag 用 v$VERSION
  2. 把 $(basename "$TARBALL") 传上去
  3. 把 sha256 填进 AUR 的 dsh-desktop-bin/PKGBUILD（或跑 updpkgsums）
EOF
