# upstream-fix

打包 DSH Desktop 时会踩到的几个坑，以及对应的处理。

本目录**不参与** [`build-release.sh`](../build-release.sh) 的正常构建 ——
它是给其他打包者的参考，尤其是维护现有 AUR 包
[`dsh-desktop-git`](https://aur.archlinux.org/packages/dsh-desktop-git) 的人。

## 一、npm 12 需要两个显式开关

`npm ci` 在 npm 12 上**必然失败**，除非加这两个开关。这不是本仓库的怪癖，
而是上游 `package-lock.json` 与 npm 12 新默认值之间的冲突：

| 开关 | 为什么需要 |
| --- | --- |
| `--allow-remote=all` | npm 12 起 `allow-remote` 默认为 `none`。lockfile 里 1113 个包的 `resolved` 指向 `registry.npmmirror.com`，与默认 registry 主机名不同 → 被判为 remote 型依赖而拒绝（`EALLOWREMOTE`） |
| `--dangerously-allow-all-scripts` | npm 12 起默认不执行依赖的 install 脚本（[RFC npm/rfcs#868](https://github.com/npm/rfcs/pull/868)），而 Electron 二进制与随包 Node 运行时正是靠 install 脚本下载的 |

这两个开关在 npm 10 / 11 上只是**未被使用的配置项，不会报错**
（已实测 npm 10.9.9 / 11.20.0 / 12.0.2）。

完整命令：

```bash
npm ci --allow-remote=all --dangerously-allow-all-scripts
```

## 二、四个缓存变量都要给

npm、`@electron/get`、`electron-builder` **各读各的缓存变量**，互不影响：

| 变量 | 谁在读 |
| --- | --- |
| `npm_config_cache` | npm |
| `electron_config_cache` | `@electron/get`（下载 Electron 二进制） |
| `XDG_CACHE_HOME` | `@electron/get` 经 `env-paths` 推导出的默认位置 |
| `ELECTRON_BUILDER_CACHE` | `electron-builder` |

在受限 HOME（CI、容器、只读家目录）下只给其中一个会漏，表现为
`ENOENT: mkdir '/home/<用户>/.cache/electron/...'` 或直接 `EROFS`。

## 三、`npm12-fix.patch`

给**现有 AUR 包** `dsh-desktop-git` 的补丁。改了 3 处：

1. 补 `options=('!strip' '!debug')` —— Electron 自带二进制不可 strip，也不需要 debug 包
2. 补上面那四个缓存变量
3. `npm ci` → 加上那两个开关

用法（在那个包的 PKGBUILD 同目录下执行）：

```bash
patch PKGBUILD < npm12-fix.patch
```

也可以直接把补丁内容贴到它的 AUR 评论区。
