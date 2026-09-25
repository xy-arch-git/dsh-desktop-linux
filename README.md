# DSH Desktop for Linux

[DSH Desktop](https://github.com/dataelement/dsh-desktop) 的 **Linux x86_64 预编译发行版**。

上游只发布 Windows（`.exe`）和 macOS（`.dmg`）安装包，**没有 Linux 二进制**。
本仓库负责把上游源码编译成 Linux 产物，并以 GitHub Releases 的形式发布，
供 [AUR](https://aur.archlinux.org/packages/dsh-desktop-bin) 的 `dsh-desktop-bin` 包和其他用户直接使用。

> **免责声明**：本仓库是独立的社区构建项目，**与上游 dataelement/dsh-desktop 及 DeepSeek 官方无隶属关系**。
> 软件著作权归上游所有，按 MIT 许可证分发。

---

## 安装

### Arch Linux（推荐）

```bash
# 从 AUR（会自动下载本仓库的 Release 产物）
yay -S dsh-desktop-bin

# 或者直接装 Release 里附带的 .pkg.tar.zst
sudo pacman -U dsh-desktop-bin-<版本>-x86_64.pkg.tar.zst
```

### 其他发行版 / 手动安装

下载 `dsh-desktop-<版本>-linux-x64.tar.zst`，解包后把 `app/` 放到任意目录，直接运行其中的 `dsh-desktop`：

```bash
tar --zstd -xf dsh-desktop-<版本>-linux-x64.tar.zst
./dsh-desktop-<版本>-linux-x64/app/dsh-desktop
```

安装 `.desktop` 与图标（可选）：

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

---

## 下载内容是什么

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

## 校验

每个 Release 都提供 `.sha256`。下载后：

```bash
sha256sum -c dsh-desktop-<版本>-linux-x64.tar.zst.sha256
```

---

## 从源码构建

不需要信任本仓库的产物 —— 你可以自己构建，或者查看
[`.github/workflows/release.yml`](.github/workflows/release.yml) 确认 CI 做了什么。

```bash
git clone https://github.com/<你的用户名>/dsh-desktop-linux.git
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

### 关于那两个 npm 开关

`npm ci` 需要两个显式开关，否则在 npm 12 上**必然失败**。这不是本仓库的怪癖，
而是上游 `package-lock.json` 与 npm 12 新默认值的冲突：

| 开关 | 为什么需要 |
| --- | --- |
| `--allow-remote=all` | npm 12 起 `allow-remote` 默认为 `none`。lockfile 里 1113 个包的 `resolved` 指向 `registry.npmmirror.com`，与默认 registry 主机名不同 → 被判为 remote 型依赖而拒绝（`EALLOWREMOTE`） |
| `--dangerously-allow-all-scripts` | npm 12 起默认不执行依赖的 install 脚本（[RFC npm/rfcs#868](https://github.com/npm/rfcs/pull/868)），而 Electron 二进制与随包 Node 运行时正是靠 install 脚本下载的 |

这两个开关在 npm 10 / 11 上只是未被使用的配置项，不会报错（已实测 npm 10.9.9 / 11.20.0 / 12.0.2）。

---

## 发布流程（维护者）

```bash
# 1. 构建
VERSION=0.9.3 ./build-release.sh

# 2. 打 tag 并推送（CI 会自动构建并创建 Release，见 workflow）
git tag v0.9.3 && git push origin v0.9.3

# 3. 更新 AUR 包
cd aur/dsh-desktop-bin
sed -i 's/^pkgver=.*/pkgver=0.9.3/' PKGBUILD
updpkgsums                       # 重算 sha256
makepkg --printsrcinfo > .SRCINFO
makepkg -f                       # 本地验证
# 然后 push 到 ssh://aur@aur.archlinux.org/dsh-desktop-bin.git
```

---

## 许可证

- 本仓库的构建脚本、workflow、打包脚本：**0BSD**（见 [LICENSE](LICENSE)）
- 被打包的 DSH Desktop 软件：**MIT**，版权归上游所有
- Release 产物中包含 Electron 与 Chromium，其许可证随产物附带
  （`app/LICENSE.electron.txt`、`app/LICENSES.chromium.html`）
