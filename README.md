# oh-my-pi Termux Patch

![oh-my-pi Termux 补丁：仅用于 Termux/Android arm64](assets/header.svg)

本仓库提供在原生 Termux / Android arm64 / Bionic libc 上安装 `@oh-my-pi/pi-coding-agent`（omp）的补丁和脚本。

仅限原生 Termux / Android arm64 / Bionic libc；不用于 Linux glibc、macOS、Windows、proot 或跨 ABI 复用。

## 产物

本仓库不提交二进制；从 GitHub Actions artifact 下载 `pi_natives.android-arm64.node`，或本地构建。
`native/` 中的 JS 适配层随仓库提供，由 `patch.sh` 安装。

## 安装

用 Bun 安装与 addon 匹配的 CLI，下载 Actions 产物后执行：

```bash
bun add -g @oh-my-pi/pi-coding-agent@19.2.1
# 下载 pi_natives.android-arm64.node 后：
./patch.sh /path/to/pi_natives.android-arm64.node
```

CLI、natives 包与 addon 版本戳必须一致。`patch.sh` 是仓库根目录脚本，只安装，不构建。

## 本地构建

```bash
./build.sh
```

可选环境变量覆盖：`UPSTREAM_REPO`、`UPSTREAM_REF`、`SRC`、`NAPI`、`OUT`。脚本结束会打印产物绝对路径。

## GitHub Actions

手动触发 `workflow_dispatch`。可选输入：

| 输入 | 默认值 |
| --- | --- |
| `upstream_repo` | `can1357/oh-my-pi` |
| `upstream_ref` | `v19.2.1` |
| `android_platform` | `android-24` |
| `src_dir` | `src` |
| `out_dir` | `src/packages/natives/native/android-build` |

补丁路径与目标 triple 是常量，不可覆盖。工作流固定 Android NDK r30、API 24、16 KiB 对齐；仅上传 `.node` 产物 `pi_natives.android-arm64.node`。

## License

MIT，见 [LICENSE](LICENSE)。
