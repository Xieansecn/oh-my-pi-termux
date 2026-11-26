# AGENTS

本文件只面向开发/维护代理；用户说明只写入 `README.md`。

## 文档边界

- `README.md` 只放用户可见内容：产物、安装、本地构建、GitHub Actions、License。
- 开发约定、平台守卫、脚本边界只写在这里，不在 README 重复安装或实现叙述。

## 默认值与覆盖

- 默认值只能来自已验证的 Termux 事实或产品常量；不要要求用户输入仓库/运行环境可判定的值。
- 有意义的输入必须可显式覆盖；用环境变量覆盖，并在赋值处一行注释来源与覆盖方式。
- 禁止隐藏回退；禁止静默指向错误平台、libc 或 ABI。

## 根目录脚本

- 根目录只保留 `build.sh` 和 `patch.sh`；不新增第二个安装或构建脚本。
- 流程用函数式小函数加 `main` 组织；除顶部常量外不使用可变全局状态。
- 失败统一用一行 `die` 报错并非零退出。
- `build.sh` 只产出 `.node`，不安装；`patch.sh` 只安装，不构建。
- 两个脚本都执行 Bionic 守卫：原生 Termux/Android arm64、`PREFIX`、`uname`、`getprop` ABI、`/system/bin/linker64`、Bun ELF interpreter；不满足时只输出一行错误退出。

## build.sh

- 产品默认值（upstream repo/ref、仓库本地缓存与源码目录、NAPI 解析、输出目录）可用显式环境变量覆盖；补丁与 addon 文件名是产品常量。
- 校验产物为 ARM aarch64、Bionic `libc.so`（不得含 `libc.so.6`）、版本戳匹配源码、可被 Bun 加载；最后打印产物绝对路径。
- 构建只生成 `.node`。

## patch.sh

- `ADDON` 是唯一必填输入，来自 `ADDON` 或第一个参数；在 `cd` 前解析为绝对路径。
- `OMP_BIN` 从 `PATH` 派生；CLI 与 natives 包按能力解析，不按路径子串判断。
- JS 补丁随仓库放在 `native/`；安装目标是解析出的 natives 包内的 `native/`。
- 版本校验要求 CLI == natives == addon 的 `__piNativesBuildVersion()`。
- 安装保持最小化：不备份、不回滚、不做 smoke 测试、不输出过程信息；成功静默。

## GitHub Actions

- 使用 `workflow_dispatch` 手动触发；仅 `upstream_repo`、`upstream_ref`、`android_platform`、`src_dir`、`out_dir` 可覆盖。
- `upstream_repo` 接受 `owner/repo` 或 GitHub URL；先归一化为 `owner/repo` 再传给 `actions/checkout`。
- 补丁路径与目标 triple 是产品常量，不是输入，也不允许覆盖。
- 在 GitHub-hosted Linux 上用 NDK 交叉编译；不调用 `build.sh`。
- NDK r30 是固定产品常量；API 24 与 16 KiB 对齐 flags 是固定常量；来源信息写入 run summary。
- 只上传 `pi_natives.android-arm64.node`；不打包 npm 包、不安装、不发布 release。

## 文档规则

- `README.md` 面向用户，`AGENTS.md` 面向代理。
- 不在 README 写开发/代理规则；不在两处重复安装叙述。
