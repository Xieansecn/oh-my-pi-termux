# oh-my-pi Termux/Android arm64 补丁与流程

本仓库保存 `@oh-my-pi/pi-coding-agent` 在原生 Termux 上跑起来的补丁、脚本和过程文档。目标版本：`v19.1.1` + Bun 1.4.5。

## 内容

- `docs/omp-android-flow.md`：从安装 CLI、定位根因、合并 PR、主动编译到运行 omp 的完整时间线与验收结果。
- `docs/omp-android-plan.md`：根因分析、方案 A/B/C 与风险记录（原始规划文档）。
- `patches/android-runtime-v19.1.1.patch`：`git diff v19.1.1..termux-19.1.1`，即上游 PR #6350 的 Android 支持合入 `v19.1.1` 后的全部源码改动（53 个文件）。
- `patches/termux-rust-1.100.patch`：本机 Rust 1.100 适配——`proc.rs` 去掉 `has_work()` 的 `const`；已包含在上一个补丁中，单独留档便于查阅。
- `patches/natives-js-android.patch`：已安装 natives 目录中 `loader-state.js` / `desktop-adapter.js` / `desktop.js` 的运行时适配（加 `android-arm64`、desktop ABI 缺失时显式报错）。
- `scripts/omp-android-build.sh`：用 `@napi-rs/cli` 编译 `pi_natives.android-arm64.node` 并打版本戳。
- `scripts/omp-android-install.sh`：备份、覆盖 JS/addon、跑 smoke test，失败自动回滚。

## 重建步骤

```bash
# 1. 准备 v19.1.1 源码
git clone --branch v19.1.1 --depth=1 https://github.com/can1357/oh-my-pi.git ~/tmp/omp-android-src

# 2. 应用 Android 源码补丁
git -C ~/tmp/omp-android-src apply ../oh-my-pi-termux/patches/android-runtime-v19.1.1.patch

# 3. 另需手工改 cargo registry 中的 audiopus_sys/build.rs：
#    把 #[cfg(any(windows, target_os = "macos", target_env = "musl"))]
#    改成含 target_os = "android"（本仓库未收录该补丁，因 registry 路径随 cargo 版本变化）

# 4. 编译并安装
~/oh-my-pi-termux/scripts/omp-android-build.sh
~/oh-my-pi-termux/scripts/omp-android-install.sh

# 5. 验收
omp --version
```

`natives-js-android.patch` 供核对使用；`omp-android-install.sh` 直接从源码 `packages/natives/native/` 拷贝这三个 JS 文件，不需要单独 apply。需要手动修复时，在 natives 目录执行 `patch -p1 < .../natives-js-android.patch`。

## 注意事项

- 两个脚本硬编码源码路径 `$HOME/tmp/omp-android-src`；换路径需先改脚本。
- 源码 natives 版本、已装 CLI 版本、addon 版本戳三者必须一致，否则 loader 拒绝加载。
- `bun add -g` 升级会覆盖 natives 目录；同版本重装后重跑安装脚本，跨版本需按新 tag 重新合并、编译。
- 失败的备份在 `~/.cache/omp-android/natives-backup-*`。
