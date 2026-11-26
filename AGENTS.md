# AGENTS

## 默认与覆盖

- 优先使用默认值；默认值只来自已验证的 Termux 事实或产品常量。
- 不要要求用户输入 Termux 或本仓库能正确判定的值。
- 有意义的用户输入必须可覆盖；用显式环境变量覆盖默认值。
- 每个默认值都在赋值处注释：为何安全、如何覆盖。
- 禁止隐藏回退；禁止静默指向错误的平台或包。

## 根目录脚本

- 根目录只保留 `build.sh` 和 `patch.sh`。
- 两者都使用小函数与 `main` 组织流程；失败统一用一行 `die` 报错并非零退出。
- 除顶部常量外，不使用可变全局状态。
- `build.sh` 只产出 `.node`，不安装；`patch.sh` 只安装，不构建。
- 不要新增第二个安装脚本或独立的构建脚本。

## build.sh

- 强制校验原生 Termux/Android arm64 与 Bionic libc：platform、arch、`PREFIX`、`uname`、`getprop` ABI、`linker64`、Bun ELF interpreter；不满足时只输出一行错误并退出。
- 产品默认值包括 upstream repo/ref、仓库本地构建缓存与源码目录、NAPI 解析方式、输出目录；均可用显式环境变量覆盖。
- Android 补丁随仓库提供，不由用户选择；addon 文件名是产品常量。
- 校验产物：ARM aarch64、Bionic libc（`libc.so`，不得有 `libc.so.6`）、版本戳匹配源码、Bun 可加载；最后打印产物绝对路径。

## patch.sh

- `ADDON` 是唯一必填用户输入，来自环境变量或第一个参数；在 `cd` 前解析为绝对路径。
- `OMP_BIN` 从 `PATH` 派生；CLI 与 natives 包按能力解析，不按路径子串判断。
- patched JS 文件随仓库放在 `native/`；安装目标是解析出的 natives 包内的 `native/`。
- 保持最小化：不备份、不回滚、不做 smoke 测试、不输出过程信息；成功时静默。
- 版本校验要求 CLI == natives == addon 的 `__piNativesBuildVersion()`。
- 使用与 `build.sh` 相同的 Bionic 校验。

## GitHub Actions

- 使用 `workflow_dispatch` 手动触发；仅 `upstream_repo`、`upstream_ref`、`android_platform`、`src_dir`、`out_dir` 可覆盖。
- `upstream_repo` 可写 `owner/repo` 或 GitHub URL；workflow 必须先归一化为 `owner/repo` 再传给 `actions/checkout`。
- 补丁路径与目标 triple 是产品常量，不是 workflow 输入，也不允许覆盖。
- 在 GitHub-hosted Linux 上通过 NDK 交叉编译；不调用 `build.sh`。
- NDK revision 是产品常量，由 workflow 固定；SDK 使用 runner 自带的 cmdline-tools/sdkmanager。
- API 24 仍是 NAPI 3.7.2 的有效基线；16 KiB 对齐 flags 是产品常量。
- 只上传 `pi_natives.android-arm64.node`；不打包 npm 包、不安装、不发布 release。
- 工具链 pin 是实现常量；来源信息写入 run summary。

## 文档

- README 保持简短：只说明工作流产物与触发方式、`./build.sh`、`./patch.sh <node>` 和可选覆盖项。
- 详细约定与约束写在 AGENTS.md，不写入 README。
