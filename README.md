# oh-my-pi Termux/Android arm64

GitHub Actions 手动触发（`workflow_dispatch`）：可选输入为 `upstream_repo`（`owner/repo` 或 GitHub URL）、`upstream_ref`、`android_platform`、`src_dir`、`out_dir`；补丁路径与目标 triple 是产品常量，不可覆盖；仅产出 `pi_natives.android-arm64.node` 作为 Actions artifact。
工作流固定 Android NDK r30、API 24 与 16 KiB 对齐。

本地 Termux 构建：

```bash
./build.sh
```

可选覆盖：`UPSTREAM_REPO`、`UPSTREAM_REF`、`SRC`、`NAPI`、`OUT`（例如 `SRC=/path/to/source ./build.sh`）。

安装下载的 addon：

```bash
./patch.sh /path/to/pi_natives.android-arm64.node
```

仓库开发指引见 [AGENTS.md](AGENTS.md)。
