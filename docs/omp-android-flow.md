# omp 在 Termux 上从零到运行的流程

记录时间：2026-11-25。环境：Termux / Android arm64，Bun 1.4.5，`@oh-my-pi/pi-coding-agent@19.1.1`。

## 结论

不是 `pkg`/`npm` 安装，而是 **Bun 全局装 CLI + 本机编译 native addon 替换**。

## 1. 安装 CLI（2026-11-24 16:38–16:55）

```bash
pnpm -g add @oh-my-pi/pi-coding-agent   # 试装后 omp 起不来，随即删除
pnpm -g rm @oh-my-pi/pi-coding-agent
bun install -g @oh-my-pi/pi-coding-agent
bun -g rm @oh-my-pi/pi-coding-agent && bun -g add @oh-my-pi/pi-coding-agent
```

结果：`~/.bun/bin/omp` 软链到 `~/.bun/install/global/node_modules/@oh-my-pi/pi-coding-agent/dist/cli.js`，版本 19.1.1。`PATH` 中 `~/.bun/bin` 在前，所以 `omp` 走 Bun 全局包。

## 2. 失败根因

- `@oh-my-pi/pi-natives` 只发布 6 个平台的预编译 addon；Termux 上 `process.platform=android` → platformTag `android-arm64` 不在 `SUPPORTED_PLATFORMS`，npm 上也没有对应 leaf 包。
- 不能走捷径：linux-arm64 的 `.node` 改名会因 glibc/bionic ABI 不兼容而 `dlopen` 失败；proot/glibc-runner 跨 libc 不行；stub 掉 native 会让 bash、grep、glob、edit、TUI 等工具失效。
- 参考：上游 issue #5975、未合并 PR #6350（`anatoli-tsinovoy/oh-my-pi` 分支 `termux-android-arm64`，19.1.0）。详细分析见 `~/omp-android-plan.md`。

## 3. 源码合并与适配（11-24 23:21 → 11-25 00:07）

源码目录：`~/tmp/omp-android-src`。

- 把 PR 分支合入官方 `v19.1.1`，建本地分支 `termux-19.1.1`；解决 `MODULE.bazel.lock` 冲突后提交 `db1d384c0b`（日志 `~/tmp/omp-android-merge.log`）。
- 为 Termux 自带 Rust 1.100 打补丁：
  - `Cargo.toml`：`rust-version = "1.101"` → `"1.100"`
  - `crates/shell/src/bash/vm/proc.rs`：`pub const fn has_work()` 去掉 `const`，避开 1.101 才稳定的 `VecDeque::is_empty()`；提交 `c0237483e2`
- 规划中还有一步：改 `audiopus_sys/build.rs`，给 `target_os = "android"` 开静态链接分支；当前 cargo 缓存中已找不到该文件，无法直接核实。
- 隔离安装构建工具：`@napi-rs/cli@3.7.2` → `~/.cache/omp-android/tools`。

## 4. 主动编译（11-25 00:07–00:43）

脚本：`~/bin/omp-android-build.sh`。核心命令：

```bash
cd ~/tmp/omp-android-src/crates/natives
CARGO_BUILD_JOBS=2 \
CMAKE_POLICY_VERSION_MINIMUM=3.5 \
PCRE2_SYS_STATIC=1 \
RUSTC_BOOTSTRAP=1 \
RUSTFLAGS='-C target-cpu=generic' \
~/.cache/omp-android/tools/node_modules/.bin/napi build \
  --manifest-path Cargo.toml \
  --package-json-path ../../packages/natives/package.json \
  --platform --no-js --dts index.d.ts \
  -o ../../packages/natives/native/android-build \
  --profile local
llvm-strip --strip-unneeded <产物>
bun ~/tmp/omp-android-src/scripts/stamp-native-version.ts <产物>
```

结果：`packages/natives/native/android-build/pi_natives.android-arm64.node`，约 114 MiB，159 个 exports，版本戳 19.1.1。耗时 35m58s（日志 `~/tmp/omp-android-build.log`）。

## 5. 安装与验收（11-25 00:44）

脚本：`~/bin/omp-android-install.sh`。行为：

1. 从 `omp` 软链解析出 Bun 全局 natives 目录 `~/.bun/install/global/node_modules/@oh-my-pi/pi-natives/native/`。
2. 校验平台为 android、源码与已装包版本一致、addon 版本戳与包版本一致。
3. 备份 `loader-state.js`、`desktop-adapter.js`、`desktop.js` 及旧 addon 到 `~/.cache/omp-android/natives-backup-<版本>-<时间>/`。
4. 用分支里的 JS 适配层覆盖三个文件：`loader-state.js` 加入 `"android-arm64"`；`desktop*.js` 在 desktop ABI 缺失时显式报错，而不是用不安全的 fallback。
5. 安装 `pi_natives.android-arm64.node`，跑 `omp --version`、`omp --help` 和 native smoke（grep / glob / executeShell / EditStore / countTokens）；任一步失败则自动回滚。

执行记录：00:44:08 第一次失败并回滚到 `natives-backup-19.1.1-20261125-004408`；00:44:33 第二次成功，备份 `...004433`，日志 `~/tmp/omp-android-install.log`。00:44:51 进入 TUI（`~/tmp/omp-tui.log`），显示 v19.1.1 欢迎页和 provider 登录页。

## 6. 当前状态（已实测）

```text
$ omp --version
omp/19.1.1
$ omp --help >/dev/null && echo HELP_OK
HELP_OK
addon: 159 exports, version=19.1.1
loader-state.js: "android-arm64" in SUPPORTED_PLATFORMS
```

## 7. 重做与升级

```bash
~/bin/omp-android-build.sh
~/bin/omp-android-install.sh
```

注意：

- 版本必须对齐：源码 natives 版本、已装 CLI 版本、addon 版本戳三者一致，否则 loader 会拒绝加载。
- `bun add -g` 升级会覆盖 natives 目录，同版本重装后重跑安装脚本即可；跨版本需按新 tag 重新合并、编译。
- 失败时从 `~/.cache/omp-android/natives-backup-*` 恢复。

## 证据文件

- 规划：`~/omp-android-plan.md`
- 构建日志：`~/tmp/omp-android-build.log`、`~/tmp/omp-android-build.status`
- 合并/提交日志：`~/tmp/omp-android-merge.log`、`~/tmp/omp-android-commit.log`
- 安装日志：`~/tmp/omp-android-install.log`
- TUI 记录：`~/tmp/omp-tui.log`
- 脚本：`~/bin/omp-android-build.sh`、`~/bin/omp-android-install.sh`
