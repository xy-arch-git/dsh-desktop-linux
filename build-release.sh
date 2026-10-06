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

# --- 1.5 给 Office 运行时补上 Linux 目标 ------------------------------------
# v0.11.0 起上游新增 office-runtime（一个随包的 Python 载荷），但它的锁只发布
# win-x64 / mac-arm64 / mac-x64。而 `npm run build` 的第一步就是 office:prepare，
# 在 Linux 上会直接抛：
#     Error: Office runtime: unsupported native target linux/x64
# 整个构建因此失败（这就是自动发布连续失败的根因）。
#
# 上游那份锁实际上是官方 deepseek-harness 的 scripts/primary-runtime/lock.json
# 的删减版：pythonVersion / pythonRelease 相同，9 个通用 wheel 的名称和哈希完全一致，
# 只是把 Linux 目标删掉了。所以这里把它补回来 —— 值取自官方锁，资源本身都在上游：
#   Python 独立构建  github.com/astral-sh/python-build-standalone
#   manylinux wheel  files.pythonhosted.org
#
# 锁里已经有 linux-x64 时（上游哪天自己加上）本步自动跳过。
LOCK="$SRC/scripts/office-runtime/lock.json"
if [[ -f "$LOCK" ]]; then
  python3 - "$LOCK" <<'PYEOF'
import json, sys
path = sys.argv[1]
lock = json.load(open(path, encoding='utf-8'))
if 'linux-x64' in lock.get('targets', {}):
    print('  Office 运行时锁已含 linux-x64，跳过')
    raise SystemExit(0)
lock['targets']['linux-x64'] = {
    "pythonTarget": "x86_64-unknown-linux-gnu",
    "pythonSha256": "72748da13197c1fb161e3afeef20a6a385ff24f2165e6e2758e47008e7faba4c",
    "wheels": [
        {"url": "https://files.pythonhosted.org/packages/b6/23/2a1b231b8ff672b4c450dac27164a8b2ca7d9b7144f9c02d2396518352eb/numpy-2.3.5-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl",
         "sha256": "0d8163f43acde9a73c2a33605353a4f1bc4798745a8b1d73183b28e5b435ae28"},
        {"url": "https://files.pythonhosted.org/packages/3d/fe/89d77e424365280b79d99b3e1e7d606f5165af2f2ecfaf0c6d24c799d607/pandas-3.0.1-cp312-cp312-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl",
         "sha256": "532527a701281b9dd371e2f582ed9094f4c12dd9ffb82c0c54ee28d8ac9520c4"},
        {"url": "https://files.pythonhosted.org/packages/84/21/a35af28dcc61f37ed850a2d64c65c701321dfbf25085e469d5559360cbbf/pillow-12.3.0-cp312-cp312-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl",
         "sha256": "78cb2c6865a35ab8ff8b75fd122f6033b92a62c82801110e48ddd6c936a45d91"},
        {"url": "https://files.pythonhosted.org/packages/db/36/aa413bc214dc4f785ad2b2ddd8cc99aae7062d49ab155e91e6011af00daf/lxml-6.1.3-cp312-cp312-manylinux2014_x86_64.manylinux_2_17_x86_64.whl",
         "sha256": "379f8a75cf6eb7eef0af074b55f49ab73b868388a98de14646abcdfa4564bb11"},
    ],
}
json.dump(lock, open(path, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
open(path, 'a', encoding='utf-8').write('\n')
print('  已补上 Office 运行时的 linux-x64 目标')
PYEOF
  log "Office 运行时锁的目标: $(python3 -c "import json;print(list(json.load(open('$LOCK'))['targets'].keys()))")"
else
  log "上游无 office-runtime 锁，跳过（v0.10.x 及更早）"
fi

# --- 1.6 修 afterPack 校验里的 Linux 可执行路径 ------------------------------
# electron-builder 打完包后，afterPack 会调 verify-packaged-ppt-runtime.cjs 做
# 一次冒烟校验。它定位「打包后的 Electron 可执行文件」用的是二元判断：
#     Windows → <appOutDir>/<product>.exe
#     其他    → <appOutDir>/<product>.app/Contents/Frameworks/<product> Helper.app/...
# 即「不是 Windows 就一定是 macOS」。Linux 上实际路径是 <appOutDir>/<executableName>，
# 于是校验抛 "Cannot locate the packaged Electron executable" —— 而那时
# dist/linux-unpacked/dsh-desktop 其实已经正常生成，构建却整体失败。
#
# 注意不能用 productFilename：那是 productName（"DSH Desktop"）sanitize 的结果，
# Linux 实际用的是 LinuxPackager.executableName —— electron-builder 里定义为
#     appInfo.sanitizedName.toLowerCase()
# 即 package.json 的 name（dsh-desktop）。所以这里直接取 packager.executableName。
#
# 这与官方 deepseek-harness 的 apps/desktop 里那个
#   platform === 'win32' ? 'electron.exe' : 'Electron.app/Contents/MacOS/Electron'
# 是同一类写法问题（同样只考虑 win/mac 两种情况）。
VERIFY="$SRC/scripts/verify-packaged-ppt-runtime.cjs"
if [[ -f "$VERIFY" ]] && ! grep -q "platform === 'linux'" "$VERIFY"; then
  python3 - "$VERIFY" <<'PYEOF'
import sys
path = sys.argv[1]
old = """  const executable = process.platform === 'win32'
    ? path.join(context.appOutDir, product + '.exe')
    : path.join(macContents, 'Frameworks', product + ' Helper.app', 'Contents', 'MacOS', product + ' Helper')"""
new = """  const executable = process.platform === 'win32'
    ? path.join(context.appOutDir, product + '.exe')
    : process.platform === 'linux'
      ? path.join(context.appOutDir, context.packager.executableName)
      : path.join(macContents, 'Frameworks', product + ' Helper.app', 'Contents', 'MacOS', product + ' Helper')"""
s = open(path, encoding='utf-8').read()
if old not in s:
    print('  ⚠ 未匹配到可执行路径判断，可能上游已改；跳过')
    raise SystemExit(0)
open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
print('  已给 afterPack 校验补上 Linux 分支')
PYEOF
  log "afterPack 校验的可执行路径已打补丁"
else
  log "afterPack 校验无需修改或已含 Linux 分支"
fi

# --- 1.7 再修两处同样的 win/mac 二元假设 -------------------------------------
# 上游在 Office 运行时这条链上又写了两处「不是 Windows 就是 macOS」：
#
#   scripts/office-runtime/prepare.mjs:91
#       platform: windows ? 'win32' : 'darwin'
#     → Linux 上把 runtime.json 的 platform 写成 'darwin'，
#       随后 afterPack 的 verifyOfficeRuntime 检查
#       `manifest.platform !== process.platform` 就抛
#       "Office runtime target mismatch"。
#
#   scripts/verify-office-runtime.cjs:41-43
#       const executable = process.platform === 'darwin' ? <mac Helper> : <appOutDir>/<product>.exe
#     → Linux 上会去找根本不存在的 <product>.exe（这里是 dsh-desktop.exe）。
#       同样应该用 packager.executableName。
#
# 两处都只在确有必要时改，已在匹配串里带上上下文避免误伤。
for pair in "prepare:scripts/office-runtime/prepare.mjs" "verify:scripts/verify-office-runtime.cjs"; do
  kind="${pair%%:*}"; rel="${pair#*:}"; f="$SRC/$rel"
  [[ -f "$f" ]] || { log "跳过 $rel（不存在）"; continue; }
  python3 - "$f" "$kind" <<'PYEOF'
import sys
path, kind = sys.argv[1], sys.argv[2]
s = open(path, encoding='utf-8').read()
if kind == 'prepare':
    old = "      platform: windows ? 'win32' : 'darwin',"
    new = "      platform: windows ? 'win32' : target.startsWith('linux-') ? 'linux' : 'darwin',"
    if new in s:
        print('  ⏭ prepare.mjs 已含 linux 分支')
    elif old in s:
        open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
        print('  ✅ prepare.mjs: manifest platform 补上 linux')
    else:
        print('  ⚠ prepare.mjs 未匹配，可能上游已改')
else:
    old = """  const executable = process.platform === 'darwin'
    ? path.join(contents, 'Frameworks', `${product} Helper.app`, 'Contents', 'MacOS', `${product} Helper`)
    : path.join(context.appOutDir, `${product}.exe`)"""
    new = """  const executable = process.platform === 'darwin'
    ? path.join(contents, 'Frameworks', `${product} Helper.app`, 'Contents', 'MacOS', `${product} Helper`)
    : process.platform === 'linux'
      ? path.join(context.appOutDir, context.packager.executableName)
      : path.join(context.appOutDir, `${product}.exe`)"""
    if "platform === 'linux'" in s:
        print('  ⏭ verify-office-runtime.cjs 已含 linux 分支')
    elif old in s:
        open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
        print('  ✅ verify-office-runtime.cjs: 可执行路径补上 linux')
    else:
        print('  ⚠ verify-office-runtime.cjs 未匹配，可能上游已改')
PYEOF
done

# --- 1.8 Linux 上没有 LibreOfficeKit 时，跳过依赖它的 Office 校验 -------------
# v0.11.0 新增的 Office 文档转换依赖 @deepseek-ai/libreoffice-kit。
# 官方（deepseek-ai）只发布了这些平台包：
#     libreoffice-kit-darwin-arm64 / darwin-x64 / win32-arm64 / win32-x64 / wasm
# 没有 linux-*（实测 npm registry：libreoffice-kit-linux-x64-glibc 返回 404）。
#
# 有意思的是官方代码是「预期」有 Linux 版的 —— 新增的
# build/office-engine-resolution.mjs 里正则写的是
#     /^@deepseek-ai\/libreoffice-kit-(?:darwin|win32|linux)-/u
# 所以这更像官方打包环节的缺口，而不是刻意不支持。
#
# 应用本身会优雅降级：office-cli capabilities 返回
#     {"code":"unavailable","error":"Installed LibreOfficeKit package is incomplete: ..."}
# 只是 afterPack 的冒烟校验把「非零退出」当成失败，导致整个构建挂掉。
#
# 这里改成：Linux 上若引擎确实不可用，就只跳过「能力探测」和「转 PDF」，
# 其余校验（载荷加载、Python 冒烟、pip check、docx/pptx/xlsx 结构检查）照常执行。
# 其他平台行为完全不变。
OFFICE_VERIFY="$SRC/scripts/verify-office-runtime.cjs"
if [[ -f "$OFFICE_VERIFY" ]] && ! grep -q 'engineAvailable' "$OFFICE_VERIFY"; then
  python3 - "$OFFICE_VERIFY" <<'PYEOF'
import sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()

old_caps = """    await execFile(executable, [cli, 'capabilities', '--json'], options)
    for (const extension of ['docx', 'pptx', 'xlsx']) {
      const input = path.join(scratch, `sample.${extension}`)
      await execFile(python, ['-I', '-B', checker, input, '--contains', 'Office runtime smoke'], options)
      await execFile(executable, [cli, 'convert', '--input', input, '--output', path.join(scratch, `${extension}.pdf`)], options)
      const pdf = await fs.readFile(path.join(scratch, `${extension}.pdf`))
      if (pdf.subarray(0, 5).toString() !== '%PDF-') throw new Error(`Office ${extension} conversion did not produce PDF`)
    }
    console.log('Packaged Office authoring, structure checks and DOCX/PPTX/XLSX PDF conversion passed')"""

new_caps = """    // Linux: 官方未发布 @deepseek-ai/libreoffice-kit-linux-*，应用会报 unavailable。
    // 此时跳过依赖 LibreOfficeKit 的能力探测与 PDF 转换，其余校验照常。
    let engineAvailable = true
    try {
      await execFile(executable, [cli, 'capabilities', '--json'], options)
    } catch (error) {
      const detail = `${error?.stdout ?? ''}${error?.stderr ?? ''}${error ?? ''}`
      if (process.platform !== 'linux' || !/libreoffice-kit-linux/u.test(detail)) throw error
      engineAvailable = false
      console.warn('[build] Linux 无官方 LibreOfficeKit 包，跳过 Office 转 PDF 校验：', detail.trim().slice(0, 300))
    }
    for (const extension of ['docx', 'pptx', 'xlsx']) {
      const input = path.join(scratch, `sample.${extension}`)
      await execFile(python, ['-I', '-B', checker, input, '--contains', 'Office runtime smoke'], options)
      if (!engineAvailable) continue
      await execFile(executable, [cli, 'convert', '--input', input, '--output', path.join(scratch, `${extension}.pdf`)], options)
      const pdf = await fs.readFile(path.join(scratch, `${extension}.pdf`))
      if (pdf.subarray(0, 5).toString() !== '%PDF-') throw new Error(`Office ${extension} conversion did not produce PDF`)
    }
    console.log(engineAvailable
      ? 'Packaged Office authoring, structure checks and DOCX/PPTX/XLSX PDF conversion passed'
      : 'Packaged Office authoring and document structure checks passed; PDF conversion skipped (no published Linux LibreOfficeKit)')"""

if new_caps in s:
    print('  ⏭ verify-office-runtime.cjs 已有 engineAvailable 逻辑')
elif old_caps in s:
    open(path, 'w', encoding='utf-8').write(s.replace(old_caps, new_caps, 1))
    print('  ✅ verify-office-runtime.cjs: Linux 上容忍 LibreOfficeKit 缺失')
else:
    print('  ⚠ verify-office-runtime.cjs 未匹配，可能上游已改；跳过')
PYEOF
  log "Office 冒烟校验已支持 Linux 降级"
else
  log "Office 冒烟校验无需修改或已支持降级"
fi

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
  # 随包 Node 运行时。上游在 v0.11.0 改了架构：不再随包独立 Node，宿主改为
  # 用 Electron 自身以 ELECTRON_RUN_AS_NODE=1 运行。其源码注释原文：
  #   The Desktop no longer ships a standalone Node.
  #   The Electron binary that runs Node work ... always with ELECTRON_RUN_AS_NODE=1.
  # （src/main/runtime/electron-node-executable.ts）
  #
  # 所以两种形态都接受，只做记录 —— 不能像以前那样把独立 Node 当硬要求：
  #   ≤ v0.10.0 → app/resources/**/node_modules/node/bin/node（独立二进制）
  #   ≥ v0.11.0 → 没有它；宿主就是 app/dsh-desktop 本身
  #
  # 注意：≥ v0.11.0 在 Linux 上有 sharp 段错误问题（electron#46323），
  # 详见 upstream-ceiling.txt —— 这里的放宽只是为了让构建流程本身不挡路。
  NODE_RT="$(find "$STAGE/app/resources" -path '*/node_modules/node/bin/node' -type f -print -quit 2>/dev/null || true)"
  if [[ -n "$NODE_RT" ]]; then
    log "随包 Node: ${NODE_RT#"$STAGE/app/"} ($(du -h "$NODE_RT" | cut -f1))"
  else
    log "无随包独立 Node —— 宿主由 Electron 自身承担（v0.11.0+ 的架构）"
  fi
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
