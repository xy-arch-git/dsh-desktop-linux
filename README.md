# DSH Desktop for Linux

[DSH Desktop](https://github.com/dataelement/dsh-desktop) 的 **Linux x86_64 构建流水线**。

## 仓库定义

**不包含 DSH Desktop 的源码，只负责编译打包。** 即：

> 把上游指定版本的源码编译成 Linux x86_64 产物，发布到本仓库的 **GitHub Releases**。

要下载安装请去 [Releases](../../releases) 或直接用 AUR，
**不要** clone 本仓库去找安装包 —— 这里只有构建配方。

## 仓库意义

上游只发布 Windows（`.exe`）与 macOS（`.dmg`），**没有 Linux 二进制**。
Linux 用户因此装不上；而 [AUR](https://aur.archlinux.org/packages/dsh-desktop-bin)
只接受构建配方、不接受二进制，所以二进制必须有地方托管。
本仓库就是那个托管方的**制造端**：构建过程公开、由 CI 执行、任何人可复现。

```
上游源码                 本仓库                     GitHub Releases        AUR
dataelement/             xy-arch-git/               (产物托管)             dsh-desktop-bin
dsh-desktop              dsh-desktop-linux
    │                         │                          │                     │
    │ tag 归档 (25MB)         │ build-release.sh         │                     │
    └────────────────────────>│ + Actions CI ───────────>│<────────────────────┘
                              │                          │   PKGBUILD 下载它
```

## 仓库内容

| 文件 | 作用 |
| --- | --- |
| `build-release.sh` | **核心**。完整构建流程：取上游源码 → `npm ci` → electron-builder 打包 → 压缩 → 算校验和。本地和 CI 调用的是**同一个脚本** |
| `.github/workflows/release.yml` | CI 编排：打 `v*` tag 时构建并创建 Release；手动触发只出 artifact |
| `.github/workflows/auto-release.yml` | **自动发布**：每天检查上游新版本，构建并发布；**会话格式变了会拒绝发布并开 issue** |
| `session-format.txt` | 会话格式基线。自动发布拿它和新构建比对，变了就停下来等人确认 |
| `LICENSE` | 0BSD，授权本仓库的构建脚本（被打包的软件仍是上游的 MIT） |
| `aur/dsh-desktop-bin/` | AUR **预编译版**配方（已发布），改完再推给 AUR |
| `aur/dsh-desktop/` | AUR **源码版**配方：使用者在本地从上游源码构建，**未发布**，作为另一条分发路径备用 |
| `upstream-fix/` |  npm 12 修复补丁 |


> ### 提供 `build-release.sh`，而非把命令直接写进 workflow的原因：
>
> 因为「构建脚本」和「CI 编排」是两件事：
>
> 1. **CI 调用同一个脚本** → 不会出现"本地能过、CI 不能过"这类只有一边才有的问题；
> 2. **不完全信任本站产物的人**可以 clone 下来跑同一个脚本，得到内容等价的产物
>    （校验方式见下方「从源码构建」）。
>
> 如果把命令内联进 workflow，这两点就都没有了 —— 你只剩一个只能在 GitHub 机器上跑的黑盒。

> **免责声明**：本仓库是独立的社区构建项目，**与上游 dataelement/dsh-desktop 及 DeepSeek 官方无隶属关系**。
> 软件著作权归上游所有，按 MIT 许可证分发。

---

## 安装

### Arch Linux（推荐）

```bash
yay -S dsh-desktop-bin
```

AUR 包会自动下载本仓库 Release 的产物，并在你的机器上打成 pacman 包
（配方见 [`aur/dsh-desktop-bin/`](aur/dsh-desktop-bin/)）。

### 手动安装（任意 Linux 发行版）

**Release 里提供的是普通压缩包，不是 pacman 包。** 解包后即可运行：

```bash
tar --zstd -xf dsh-desktop-<版本>-linux-x64.tar.zst
./dsh-desktop-<版本>-linux-x64/app/dsh-desktop
```

想装进系统目录（可选，把 `<版本>` 换成实际版本号）：

```bash
D=dsh-desktop-<版本>-linux-x64
sudo install -d /opt/dsh-desktop
sudo cp -r "$D/app/." /opt/dsh-desktop/
sudo ln -sf /opt/dsh-desktop/dsh-desktop /usr/bin/dsh-desktop
sudo install -Dm644 "$D/dsh-desktop.desktop" /usr/share/applications/dsh-desktop.desktop
for p in "$D"/icons/*.png; do
  s=$(basename "$p" .png)
  sudo install -Dm644 "$p" "/usr/share/icons/hicolor/$s/apps/dsh-desktop.png"
done
```

**Arch 用户如果不想用 AUR**，也可以直接用本仓库的 PKGBUILD 自己打包：

```bash
git clone https://github.com/xy-arch-git/dsh-desktop-linux.git
cd dsh-desktop-linux/aur/dsh-desktop-bin
makepkg -si
```

---

## Release内容

每个 Release 附带的 `dsh-desktop-<版本>-linux-x64.tar.zst` 解包后结构固定：

```
dsh-desktop-<版本>-linux-x64/
├── app/                      整个 Electron 应用（含 Electron 43 与随包 Node 24.9 运行时）
├── dsh-desktop.desktop       桌面启动项
├── icons/                    16~512 的 PNG 图标
└── LICENSE                   上游 MIT 许可证
```

**运行依赖**（Electron 在 Linux 上所需，AUR 包已声明）：

```
alsa-lib at-spi2-core brotli c-ares flac fontconfig freetype2 gcc-libs glibc gtk3
harfbuzz libdrm libevent libffi libjpeg-turbo libnotify libpulse libsecret
libxcomposite libxdamage libxkbcommon libxrandr libxss libxtst libxml2 libxslt
minizip nss opus util-linux xdg-utils zlib
```

托盘图标另需 `libappindicator-gtk3`；Wayland 下屏幕共享另需 `pipewire`（均为可选）。

---

## 兼容性

**glibc 要求：≥ 2.28（2018 年发布）**，已实测确认。

实测方法：对压缩包内全部 20 个 ELF 文件读取动态符号版本，最高要求为 `GLIBC_2.28`。

```
chrome-sandbox           GLIBC_2.4      libEGL.so / libGLESv2.so    GLIBC_2.16~2.17
dsh-desktop              GLIBC_2.25     libffmpeg.so                GLIBC_2.17
node (随包运行时)         GLIBC_2.28     node-pty/prebuilds/...      GLIBC_2.28
sharp-libvips            GLIBC_2.28     koffi / system.node         GLIBC_2.4~2.17
```

之所以这么低，是因为**没有任何组件是在构建机上编译的**：Electron 与 Node 是官方预编译产物，
`node-pty` / `koffi` / `sharp` / `ripgrep` 都是「平台-架构」维度的预编译 N-API 包。
因此本产物可在任何近年更新过的 x86_64 Linux 上运行。

> ### 关于可复现性
>
> 本产物**不是可复现构建**。实测：同一份源码、同一个 `build-release.sh`，
> 两次构建出的 `tar.zst` **sha256 不同** —— 因为 tar 会记录文件 mtime。
> 已验证两次产物的**内容完全一致**（`app/dsh-desktop` 哈希、文件清单、
> `.desktop` 内容均逐字节相同），但压缩包字节不同。
>
> 实际含义：你能用校验和确认**下载完整**，但**无法独立确认产物与上游源码的对应关系**，
> 只能信任本仓库。构建流程全部公开（[`build-release.sh`](build-release.sh) +
> [`.github/workflows/release.yml`](.github/workflows/release.yml)），
> CI 日志与产物可查。想完全避免这层信任，请按上面的「从源码构建」自己构建，
> 或使用 AUR 的源码包 `dsh-desktop`。

---

## 自动发布与「会话格式闸门」

`.github/workflows/auto-release.yml` 每天检查上游有没有新版本，有就自动构建并发布。

**发布前事宜**：比对新构建捆绑的 DSH 会话格式版本与 `session-format.txt` 里的基线。

DSH 的会话格式是**硬闸门**——每个构建只读自己那一个版本（见
`dsh-session-persistence` 的 `sessionFormatVersionRefusal`）。格式一变，
用户升级后历史会话就全部打不开，报：

> the log was written by a newer harness — upgrade the harness to open it

而升级软件包**不会**动用户数据目录，所以这个错会输出给用户。

**格式没变** → 自动发布。
**格式变了** → 拒绝发布 + 开一个 issue 告诉你；你确认要接受时，把
`session-format.txt` 改成新值再跑一次即可。

格式版本是从产物里 `@deepseek-ai/dsh-session/lib/index.js` 的
`SESSION_FORMAT_VERSION = N` 直接读出来的（不执行代码）。

## 下载很慢或被中断？

Release 产物约 **194 MB**，托管在 GitHub Releases。从中国大陆访问 GitHub 时可能很慢，
甚至中途断开（`curl: (56) ... unexpected eof while reading`）。

**下载支持断点续传**，断了就重跑同一条命令，会从断点继续：

```bash
V=0.9.2          # ← 改成实际版本号；文件名要和 Release 上的资产名一致
curl -L -C - --retry 5 -O \
  "https://github.com/xy-arch-git/dsh-desktop-linux/releases/download/v$V/dsh-desktop-$V-linux-x64.tar.zst"
```

用 AUR 包的用户如果卡在下载阶段，可以先把文件续传下到 makepkg 的 `SRCDIR`，
再跑 `makepkg -f` —— 它会直接复用已经下好的文件：

```bash
# 文件名必须和 PKGBUILD 里 source= 的第一段一致
curl -L -C - --retry 5 -o dsh-desktop-bin-0.9.2.tar.zst \
  https://github.com/xy-arch-git/dsh-desktop-linux/releases/download/v0.9.2/dsh-desktop-0.9.2-linux-x64.tar.zst
```

## 校验

每个 Release 都提供 `.sha256`。下载后：

```bash
V=0.9.2          # ← 改成实际版本号
sha256sum -c "dsh-desktop-$V-linux-x64.tar.zst.sha256"
```

---

## 从源码构建

不需要信任本仓库的产物 —— 你可以自己构建，或者查看
[`.github/workflows/release.yml`](.github/workflows/release.yml) 确认 CI 做了什么。

```bash
git clone https://github.com/xy-arch-git/dsh-desktop-linux.git
cd dsh-desktop-linux
./build-release.sh
```

构建脚本做的事（约 1GB 下载、10 分钟左右）：

1. 下载上游 `v<版本>` 的 tag 归档（约 25MB，比全量 `git clone` 小 30 倍）
2. `npm ci --allow-remote=all --dangerously-allow-all-scripts`
3. `npm run package:dir`（electron-vite build + electron-builder --dir）
4. 组装发布树（app / .desktop / icons / LICENSE）
5. 压成 `tar.zst` 并生成 sha256

版本由环境变量指定：

```bash
VERSION=0.9.3 ./build-release.sh
```

那两个 npm 开关为什么需要、受限环境还要补哪些缓存变量，
见 [`upstream-fix/`](upstream-fix/)。

---

## 许可证

- 本仓库的构建脚本、workflow、打包脚本：**0BSD**（见 [LICENSE](LICENSE)）
- 被打包的 DSH Desktop 软件：**MIT**，版权归上游所有
- Release 产物中包含 Electron 与 Chromium，其许可证随产物附带
  （`app/LICENSE.electron.txt`、`app/LICENSES.chromium.html`）
