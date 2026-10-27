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
# v0.11.0 新增 office-runtime，但它的锁只发布 win/mac 目标，于是 `npm run build`
# 的第一步 office:prepare 在 Linux 上直接抛 "unsupported native target linux/x64"。
# 该锁是官方 deepseek-harness primary-runtime/lock.json 的删减版（pythonVersion 与
# 9 个通用 wheel 的名称、哈希完全一致），下面的值即取自那份官方锁。
# 锁里已有 linux-x64 时自动跳过。
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
# verify-packaged-ppt-runtime.cjs 用二元判断定位打包后的 Electron：Windows 取
# <product>.exe，其余一律走 macOS Helper 路径。Linux 上实际是
# <appOutDir>/<executableName> —— 注意不是 productFilename（那是 "DSH Desktop"，
# Linux 用的是包名 dsh-desktop）。
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
#   office-runtime/prepare.mjs    platform: windows ? 'win32' : 'darwin'
#   verify-office-runtime.cjs     非 darwin 一律找 <appOutDir>/<product>.exe
# 前者把 runtime.json 写成 darwin（随后触发 target mismatch），后者找不到可执行文件。
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

# --- 1.8 Linux 无 LibreOfficeKit 时，跳过依赖它的 Office 校验 -----------------
# 官方只发布了 libreoffice-kit 的 darwin / win32 / wasm 平台包，没有 linux-*
# （实测 npm registry 返回 404）。应用会优雅降级报 unavailable，但 afterPack 把
# 非零退出当失败。这里只跳过「能力探测」与「转 PDF」，载荷加载、Python 冒烟、
# pip check 照常执行；其他平台行为不变。
OFFICE_VERIFY="$SRC/scripts/verify-office-runtime.cjs"
if [[ -f "$OFFICE_VERIFY" ]] && ! grep -q 'engineAvailable' "$OFFICE_VERIFY"; then
  python3 - "$OFFICE_VERIFY" <<'PYEOF'
import sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()

# 1) capabilities 调用外包一层 Linux 容错
old_cap = "    await execFile(executable, [cli, 'capabilities', '--json'], options)"
new_cap = """    // Linux: 官方未发布 @deepseek-ai/libreoffice-kit-linux-*，应用会报 unavailable。
    let engineAvailable = true
    try {
      await execFile(executable, [cli, 'capabilities', '--json'], options)
    } catch (error) {
      const detail = `${error?.stdout ?? ''}${error?.stderr ?? ''}${error ?? ''}`
      if (process.platform !== 'linux' || !/libreoffice-kit-linux/u.test(detail)) throw error
      engineAvailable = false
      console.warn('[build] Linux 无官方 LibreOfficeKit 包，跳过 Office 转 PDF 校验：', detail.trim().slice(0, 300))
    }"""

# 2) 循环开头加短路（锚点对 v0.11/v0.12 都成立）
old_loop = "    for (const extension of ['docx', 'pptx', 'xlsx']) {"
new_loop = old_loop + "\n      if (!engineAvailable) continue"

# 0) Linux 上整段跳过：Office 依赖的 LibreOfficeKit 没有官方 Linux 构建，
#    功能本就不存在；而 probe.cjs 需要 workspace-write 沙箱后端，在 CI runner 上
#    （bubblewrap 受 AppArmor 限制、无 Landlock）必然失败。
old_ap = "async function afterPack(context) {"
new_ap = '''async function afterPack(context) {
  // Linux: Office 功能不可用（无官方 LibreOfficeKit），跳过整段运行时校验。
  if (process.platform === 'linux') {
    console.warn('[build] Linux 上跳过 Office 运行时校验（无 LibreOfficeKit）')
    return
  }'''
if new_ap in s:
    print('  ⏭ afterPack 已含 Linux 跳过')
elif old_ap in s:
    s = s.replace(old_ap, new_ap, 1)
    print('  ✅ afterPack 在 Linux 上整段跳过')
else:
    print('  ⚠ afterPack 锚点未匹配')

if new_cap in s:
    print('  ⏭ 已有 engineAvailable 逻辑')
elif old_cap in s and old_loop in s:
    s = s.replace(old_cap, new_cap, 1).replace(old_loop, new_loop, 1)
    open(path, 'w', encoding='utf-8').write(s)
    print('  ✅ verify-office-runtime.cjs: Linux 上容忍 LibreOfficeKit 缺失')
else:
    print('  ⚠ 锚点未匹配，可能上游又改了；跳过')
PYEOF
  log "Office 冒烟校验已支持 Linux 降级"
else
  log "Office 冒烟校验无需修改或已支持降级"
fi

# --- 1.9 恢复随包独立 Node（Linux 上绕开 Electron 的 sharp 段错误）-------------
# 上游自 v0.11.0 起让宿主跑在 Electron 自身里（ELECTRON_RUN_AS_NODE=1）。Electron 的
# Linux 二进制会动态链接全局 glib 并把符号泄漏进进程空间，与 sharp 的 libvips 冲突
# → SIGSEGV（electron#46323，未修）。v0.10.0 用随包独立 Node 时正常，这里把它加回来。
#
# 关键：0.12.1 把整个运行时打进 app.asar（352MB），而
#   bundledRuntimeRoot() = app.getAppPath()   ← 返回「app.asar 这个文件」
# 它有 14 处使用（dshEntryPath / bundledNodePath / pnpm / presets / node_modules…），
# 只修一处不够。所以直接改 bundledRuntimeRoot()：打包时指向 app.asar.unpacked。
# 同时因为宿主跑在普通 Node 上（无 asar 支持），node_modules 必须全量解包。
if [[ -f "$SRC/src/main/index.ts" ]] && grep -q '^function bundledRuntimeRoot(): string {' "$SRC/src/main/index.ts"; then
  python3 - "$SRC" <<'PYEOF'
import json, pathlib, sys
src = pathlib.Path(sys.argv[1])

idx = src / 'src/main/index.ts'
s = idx.read_text(encoding='utf-8')

old_root = """function bundledRuntimeRoot(): string {
  return app.getAppPath()
}"""
new_root = """function bundledRuntimeRoot(): string {
  // 0.12.1 把运行时打进了 app.asar，而 app.getAppPath() 返回的是 app.asar 这个
  // 「文件」，下面所有拼 node_modules 的地方都会失效。宿主跑在随包独立 Node 上
  //（没有 asar 支持），node_modules 已 asarUnpack 出来，所以打包时指向 unpacked。
  return app.isPackaged
    ? join(process.resourcesPath, 'app.asar.unpacked')
    : app.getAppPath()
}"""
if 'app.asar.unpacked' in s.split('function bundledRuntimeRoot')[1][:300]:
    print('  ⏭ bundledRuntimeRoot 已修')
elif old_root in s:
    idx.write_text(s.replace(old_root, new_root, 1), encoding='utf-8')
    print('  ✅ bundledRuntimeRoot 打包时指向 app.asar.unpacked（一处修好 14 处）')
else:
    print('  ⚠ bundledRuntimeRoot 未匹配，可能上游已改')
    raise SystemExit(0)

s = idx.read_text(encoding='utf-8')
old_node = """function bundledNodePath(): string {
  return electronNodeExecutable(process.execPath)
}"""
new_node = """function bundledNodePath(): string {
  // 不用 Electron 跑 Node：其 Linux 二进制会泄漏 glib 符号，与 sharp 的 libvips
  // 冲突导致段错误（electron/electron#46323）。用随包独立 Node。
  const executable = process.platform === 'win32' ? 'node.exe' : 'node'
  return join(bundledRuntimeRoot(), 'node_modules', 'node', 'bin', executable)
}"""
if old_node in s:
    idx.write_text(s.replace(old_node, new_node, 1), encoding='utf-8')
    print('  ✅ bundledNodePath 指回随包独立 Node')

pkg_path = src / 'package.json'
pkg = json.loads(pkg_path.read_text(encoding='utf-8'))
# electron-builder 只打包 package.json 里声明为 dependencies 的包；
# 不声明的话 node_modules/node 会被当成多余目录丢掉（0.12.1-4 就是这么失败的）。
deps = pkg.setdefault('dependencies', {})
if 'node' not in deps:
    deps['node'] = '24.9.0'
    print('  ✅ dependencies 加回 node@24.9.0')
# dsh-ppt 声明依赖 typescript，但它只是根 devDependency，打包时会被剪掉，
# afterPack 的依赖校验就会报「Packaged dependency typescript is missing」。
# 提到 dependencies 让它进包。
if 'typescript' not in deps:
    deps['typescript'] = '5.9.3'
    print('  ✅ dependencies 加 typescript（dsh-ppt 的运行时依赖）')
# 必须同时从 devDependencies 删掉：同一个包同时出现在两处时，electron-builder
# 仍按 dev 依赖剪掉，产物里就没有 typescript，afterPack 校验会失败。
dev = pkg.get('devDependencies') or {}
if 'typescript' in dev:
    dev.pop('typescript')
    pkg['devDependencies'] = dev
    print('  ✅ devDependencies 移除 typescript（否则仍会被剪掉）')
# ppt 的 from/to 注入内容不走 asarUnpack（实测：加了显式规则也不解包），
# 而宿主跑在普通 Node 上读不到 asar 内的模块。改为在打包前把构建产物直接
# cp 进 node_modules（见下面的「打包」步骤），这里同步去掉注入与排除规则。
files_cfg = pkg['build'].get('files')
if isinstance(files_cfg, list):
    cleaned = []
    for item in files_cfg:
        if isinstance(item, str) and item in ('!node_modules/dsh-ppt{,/**}', '!node_modules/dsh-ppt-composer{,/**}'):
            continue
        if isinstance(item, dict) and str(item.get('to', '')).startswith('node_modules/dsh-ppt'):
            continue
        cleaned.append(item)
    if len(cleaned) != len(files_cfg):
        pkg['build']['files'] = cleaned
        print('  ✅ files 去掉 ppt 的排除项与 from/to 注入')
au = pkg['build'].setdefault('asarUnpack', [])
# 宿主跑在独立 Node 上，普通 Node 没有 asar 支持：代码留在 app.asar 里就读不到。
# 必须全量解包 node_modules（0.10.0 就是这么做的，它的 app.asar 只有 6.1MB）。
changed = False
if 'node_modules/**/*' not in au:
    au.append('node_modules/**/*')
    changed = True
    print('  ✅ asarUnpack 加 node_modules/**/*（全量解包）')
# electron-builder 用 files 的 from/to 注入的这两个包，node_modules/**/* 覆盖不到，
# 会被打进 app.asar；而宿主跑在独立 Node 上，读不到 asar 内的模块，必须显式解包。
for pat in ('node_modules/dsh-ppt/**/*', 'node_modules/dsh-ppt-composer/**/*'):
    if pat not in au:
        au.append(pat)
        changed = True
        print(f'  ✅ asarUnpack 加 {pat}')
if changed:
    pkg_path.write_text(json.dumps(pkg, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
PYEOF
  ( cd "$SRC" && npm install --package-lock-only --ignore-scripts --no-audit --no-fund >/dev/null 2>&1 \
      || die "同步 package-lock.json 失败" )
  log "已恢复随包独立 Node + 修正运行时根，并同步锁文件"
else
  log "上游结构已变，跳过 1.9"
fi

# --- 1.10 修 verify-packaged-harness.cjs 里同样的可执行路径判断 -----------------
# v0.12.x 新增的 afterPack 校验，写法与之前几处相同（非 darwin 一律取 <product>.exe）。
VERIFY_HARNESS="$SRC/scripts/verify-packaged-harness.cjs"
if [[ -f "$VERIFY_HARNESS" ]] && ! grep -q "electronPlatformName === 'linux'" "$VERIFY_HARNESS"; then
  python3 - "$VERIFY_HARNESS" <<'PYEOF'
import sys
path = sys.argv[1]
s = open(path, encoding='utf-8').read()
old = """  const executable = context.electronPlatformName === 'darwin'
    ? path.join(contents, 'Frameworks', `${product} Helper.app`, 'Contents', 'MacOS', `${product} Helper`)
    : path.join(context.appOutDir, `${product}.exe`)"""
new = """  const executable = context.electronPlatformName === 'darwin'
    ? path.join(contents, 'Frameworks', `${product} Helper.app`, 'Contents', 'MacOS', `${product} Helper`)
    : context.electronPlatformName === 'linux'
      ? path.join(context.appOutDir, context.packager.executableName)
      : path.join(context.appOutDir, `${product}.exe`)"""
if new in s:
    print('  \u23ed 已含 linux 分支')
elif old in s:
    open(path, 'w', encoding='utf-8').write(s.replace(old, new, 1))
    print('  \u2705 verify-packaged-harness.cjs: 可执行路径补上 linux')
else:
    print('  \u26a0 未匹配，可能上游已改')
PYEOF
  log "harness 校验的可执行路径已打补丁"
else
  log "harness 校验无需修改或已含 Linux 分支"
fi

# --- 1.11 Linux 无 LibreOfficeKit 时跳过 Office 模板预览校验 -------------------
# v0.12.x 的 PPT 运行时校验会调 renderOfficeTemplatePreview，它依赖 LibreOfficeKit
# ——官方同样没有 linux-* 包。只跳过这一段，前面的预览清单、PPT 结构校验照常。
VERIFY_PPT="$SRC/scripts/verify-packaged-ppt-runtime.cjs"
if [[ -f "$VERIFY_PPT" ]] && ! grep -q '无需 LibreOfficeKit' "$VERIFY_PPT"; then
  python3 "$(dirname "${BASH_SOURCE[0]}")/patch-office-preview.py" "$VERIFY_PPT" || true
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
# 分三步而不是 `npm run package:dir`：ppt 的构建产物要先落进 node_modules，
# 才能被 asarUnpack 解包（electron-builder 的 files from/to 注入不吃 asarUnpack）。
log "构建（office:prepare + ppt:build + electron-vite build）"
( cd "$SRC" && npm run build )

log "把 ppt 构建产物放进 node_modules"
# 注意：构建产物里的 package.json 带着开发期依赖（如 typescript），而这些没装，
# afterPack 的依赖校验会报「Packaged dependency typescript is missing」。
# 这里清掉 devDependencies，并丢弃 node_modules 里不存在的运行时依赖。
for pkg in dsh-ppt dsh-ppt-composer; do
  src="$SRC/.build/ppt-runtime/packages/$pkg"
  [[ -d "$src" ]] || die "缺少 ppt 构建产物：$pkg"
  rm -rf "$SRC/node_modules/$pkg"
  cp -r "$src" "$SRC/node_modules/$pkg"
  python3 - "$SRC/node_modules/$pkg/package.json" "$SRC/node_modules" <<'PYEOF'
import json, os, sys
pkg_path, nm = sys.argv[1], sys.argv[2]
d = json.load(open(pkg_path, encoding='utf-8'))
d.pop('devDependencies', None)
deps = d.get('dependencies') or {}
dropped = [k for k in deps if not os.path.isdir(os.path.join(nm, *k.split('/')))]
for k in dropped:
    deps.pop(k, None)
if dropped:
    print(f'    {os.path.basename(pkg_path)}: 丢弃未安装的依赖 {dropped}')
if deps or 'dependencies' in d:
    d['dependencies'] = deps
json.dump(d, open(pkg_path, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)
open(pkg_path, 'a', encoding='utf-8').write('\n')
PYEOF
done

log "electron-builder --dir"
( cd "$SRC" && npx electron-builder --dir )

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
    # 随包 Node。上游 v0.11.0 起不再随包独立 Node，宿主改用 Electron 自身
    # （ELECTRON_RUN_AS_NODE=1）。两种形态都接受，只做记录：
    #   ≤ v0.10.0 → app/resources/**/node_modules/node/bin/node
    #   ≥ v0.11.0 → 没有它，宿主就是 app/dsh-desktop 本身
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
