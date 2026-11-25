# omp (oh-my-pi) 在 Termux/Android arm64 上启动失败的修复规划

## 实施结果（2026-11-25）：已修复

- 未降级：当前仍是 `@oh-my-pi/pi-coding-agent@19.1.1` + Bun 1.4.5。
- 将 PR #6350 的 Android 支持合入官方 `v19.1.1`，源码在 `~/tmp/omp-android-src`，本地分支 `termux-19.1.1`。
- 为本机 Rust 1.100 做了两处适配：`Cargo.toml` 的 rust-version 改为 1.100；
  `crates/shell/src/bash/vm/proc.rs` 的 `Vproc::has_work()` 去掉 `const`，避开 1.101 才稳定的 `VecDeque::is_empty()`。
- 已生成并安装 `pi_natives.android-arm64.node`（约 114 MiB，159 个 exports，版本戳 19.1.1）。
- 验证通过：`omp --version`、`omp --help`、TUI 欢迎页，以及 native 的 grep / glob / executeShell / EditStore / countTokens。
- 构建脚本：`~/bin/omp-android-build.sh`；安装与回滚脚本：`~/bin/omp-android-install.sh`。
- 安装前原始 JS 备份：`~/.cache/omp-android/natives-backup-19.1.1-20261125-004433`。
- 注意：`bun add -g` 升级会覆盖这些修改；同版本重装后运行安装脚本即可，升级到新版本需按新 tag 重新合并、编译。

## 0. 根因（一句话版）

`@oh-my-pi/pi-natives` 只发布 6 个平台的预编译 addon（linux/darwin/win32 × x64/arm64），
loader 用 `process.platform` 拼 platformTag，Termux 上得到 `android-arm64`：

- `SUPPORTED_PLATFORMS` 里没有 `android-arm64` → 直接 throw（就是当前报错）；
- npm 上也没有 `@oh-my-pi/pi-natives-android-arm64` 这个 leaf 包（404），
  所以「改 loader 允许 android」也没东西可加载。

不能用的捷径：
- 把 linux-arm64 的 `.node` 改名成 android-arm64：glibc vs bionic ABI 不兼容，`dlopen` 必挂；
- glibc-runner / proot 里加载：addon 必须被 **android 版 bun** dlopen，跨 libc 不行；
- 把 native 模块 stub 掉：`bash`(Shell/executeShell/Process)、`grep`、`glob`、`edit`(EditStore)、
  `TUI`(TtyWriter) 全部依赖 native，stub 后 omp 只能读文件+聊天，工具基本残废。

所以真正的修复只有两条路：**给 android 编出真正的 addon**，或**换到有预编译包的运行环境**。

## 已确认的现状（2026-11-24）

| 项 | 值 |
|---|---|
| 本机 bun | `~/.local/bin/bun` 1.4.5 (android arm64) |
| 已装 omp | `@oh-my-pi/pi-coding-agent@19.1.1`（bun global） |
| natives 路径 | `~/.bun/install/global/node_modules/@oh-my-pi/pi-natives/native/` |
| 上游 issue | can1357/oh-my-pi#5975「publish native Android ARM64 addon for Termux」 |
| 上游 PR | can1357/oh-my-pi#6350「feat(android): support Termux native runtime」**open，未合并** |
| PR 分支 | `anatoli-tsinovoy/oh-my-pi` @ `termux-android-arm64`，当前版本 19.1.0 |
| Termux rust | `pkg` 里是 1.100.0，而仓库要求 `rust-version = "1.101"`（需要绕过） |
| 作者验证记录 | 在原生 Termux 上构建成功过（omp 17.2.10，73 个 native exports，`omp --version/--help` 通过） |

也就是说：**方案是现成的社区分支，缺的是在 19.1.x 上把它跑通**。

---

## 方案 A（推荐）：在 Termux 本机交叉编译 android-arm64 addon

用 PR #6350 的源码，本机 `cargo/napi` 编出 `pi_natives.android-arm64.node`，塞进已安装的包。
一次投入 ~30–45 分钟编译（作者原话），之后升级 omp 可能要重来。

### A1. 准备工具链

```bash
pkg install rust clang cmake make nodejs-lts pkg-config git llvm
```

### A2. 拉源码

```bash
git clone --depth=1 --single-branch -b termux-android-arm64 \
  https://github.com/anatoli-tsinovoy/oh-my-pi.git ~/.cache/omp-android/src
```

### A3. 打 3 个必要补丁（相对作者当年的脚本，crate 路径和 rust 版本变了）

1. **rust 版本**：`Cargo.toml` 的 `rust-version = "1.101"` 改 `"1.100"`。
   （或者给 cargo 传 `--ignore-rust-version`；napi CLI 不一定透传，改文件最稳。）
2. **crate 路径**：老脚本写的是 `crates/pi-natives`，现在是 `crates/natives`。
3. **audiopus_sys**：`opus` 依赖的 build.rs 没给 android 开静态链接分支，
   在 `~/.cargo/registry/.../audiopus_sys-*/build.rs` 里把
   `#[cfg(any(windows, target_os = "macos", target_env = "musl"))]`
   改成含 `target_os = "android"`。作者脚本里 `patch_audiopus_sys_android()` 就是做这个。

### A4. 编 addon

```bash
pkg install nodejs-lts    # 只为 npm 装 @napi-rs/cli
mkdir -p ~/.cache/omp-android/tools && cd ~/.cache/omp-android/tools
npm install --ignore-scripts "@napi-rs/cli@3.7.2"

cd ~/.cache/omp-android/src/crates/natives
CARGO_BUILD_JOBS=1 \
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
```

产物：`packages/natives/native/android-build/pi_natives.android-arm64.node`

```bash
llvm-strip --strip-unneeded pi_natives.android-arm64.node
bun -e 'const a=require(process.argv[1]);console.log(Object.keys(a).length,"exports")' \
  "$PWD/pi_natives.android-arm64.node"
```

`--profile local` 是仓库自带 profile（release 继承、thin LTO、不 strip），比 `release` 的 fat LTO 快很多。
`CARGO_BUILD_JOBS=1` 是作者建议的防 OOM 设置（本机 15G 内存、8 核，可先试 2–4）。

### A5. 安装到已装的 omp

注意版本必须对齐 loader 的校验：**分支是 19.1.0，本机装的是 19.1.1**。

```bash
# 二选一：(a) 装同版本 CLI；(b) 保留 19.1.1 并让 loader 放行（见下）
bun add -g @oh-my-pi/pi-coding-agent@19.1.0
```

然后把 addon 和分支里的 JS 适配层一起覆盖（android 上 desktop/clipboard 是被裁掉的，
分支改了 `desktop-adapter.js` / `desktop.js` 才能通过 release 校验）：

```bash
N=~/.bun/install/global/node_modules/@oh-my-pi/pi-natives/native
cp ~/.cache/omp-android/src/packages/natives/native/*.js  $N/
cp ~/.cache/omp-android/src/packages/natives/native/*.d.ts $N/
install -m755 ~/.cache/omp-android/src/packages/natives/native/android-build/pi_natives.android-arm64.node \
  $N/pi_natives.android-arm64.node
# SUPPORTED_PLATFORMS 加 "android-arm64"（分支已改，若用上游 JS 就手动加）
grep -n 'const SUPPORTED_PLATFORMS' -A3 $N/loader-state.js
```

版本仍不匹配时（loader 会报 "reports no release version / different release"）：
最小补丁是 `initLoaderContext()` 里的 `isWorkspaceLoad` 判定，或直接让 `validateLoadedBindings` 在
`process.platform === "android"` 时 return —— 本地一次性改动，升级会被覆盖。

### A6. 验收

```bash
omp --version
omp --help >/dev/null && echo HELP_OK
omp            # TUI 起来后跑一次 bash 工具、grep、edit，确认 native 调用链通
```

### A 的风险

- 分支基于 19.1.0，代码落后/领先 19.1.1 一点，可能出现符号缺失（`<sym> is not a function`）；
- 首次编译 30–45 min，磁盘 2–3 GB，Termux 上 rust 1.100 编译 `edition 2024 + 1.101` 代码需要验证；
- 每次 `bun add -g` 升级 omp 都会把 natives 目录覆盖回去，**需要重新拷贝 addon + 重打 loader 补丁**。
  可以把 A5 写成 `~/bin/omp-natives-refresh.sh` 方便复用。

---

## 方案 B：Linux 主机交叉编译（上游倾向的「二进制分发」路线）

PR #6350 加了一个显式 bazel 目标和一个独立二进制构建：

```bash
ANDROID_NDK_HOME=/path/to/android-ndk25b+ bun scripts/bazel-natives.ts android-arm64
ANDROID_NDK_HOME=/path/to/android-ndk25b+ bun --cwd=packages/coding-agent run build:android
# → packages/coding-agent/dist/omp-android-arm64 （内嵌 Bun 1.4.4 + addon，单文件）
```

- 需要 **x86_64 Linux 构建机 + Bazel + NDK 25b+**，Termux 上跑 Bazel 不现实；
- 最省事的替代：把这套流程丢到 **GitHub Actions（自己的 fork）** 上跑，下载 artifact 推到手机；
- 优点：产物是自包含二进制，不需要 Termux 里有 rust，也不怕 `bun add -g` 覆盖；
- 缺点：要一台 Linux/CI；bazel 依赖树完整拉一遍很重（数 GB）。

如果只是自己用，方案 A 更短；如果要做「长期可重复」，B 才是正解。

---

## 方案 C：proot-distro 里用官方 linux-arm64（零构建，今天就能跑）

```bash
pkg install proot-distro
proot-distro install debian
proot-distro login debian
# 容器内：
apt update && apt install -y curl unzip git
curl -fsSL https://bun.sh/install | bash
bun add -g @oh-my-pi/pi-coding-agent
omp
```

- 容器里 `process.platform === "linux"`，`@oh-my-pi/pi-natives-linux-arm64` 正常安装，无需编译；
- 风险：Bun 的 JSC JIT 在 proot 下偶发 `mmap`/`W^X` 问题；性能有折扣；`$HOME` 路径要 bind
  （`proot-distro login debian --bind ~:/termux-home`）才能改手机上的项目；
- 适合「先确认 omp 值不值得折腾」，不适合长期日用。

---

## 建议的落地顺序

1. **今天**：方案 C 花 20 分钟验证 omp 在你的设备上是否可用（尤其 TUI 和 bash 工具），顺便确认值不值得继续；
2. **本周**：按方案 A 编一次 android addon（作者验证过可行，只是要适配 19.1.x），把 A5 固化成脚本；
3. **顺带**：在 issue #5975 / PR #6350 下面留言 +1 并附上 19.1.1 的构建结果 ——
   上游合并 + npm 发布 `pi-natives-android-arm64` 才是最终解，之后 `bun add -g` 就能直接用；
4. 如果长期重度使用，走 B（CI 出二进制），彻底摆脱「升级即失效」。

## 参考

- issue #5975: https://github.com/can1357/oh-my-pi/issues/5975
- PR #6350: https://github.com/can1357/oh-my-pi/pull/6350
- PR 评论里的完整构建脚本（作者原版，含 `install_omp()` / `patch_audiopus_sys_android()`）：
  https://github.com/can1357/oh-my-pi/pull/6350#issuecomment-（2026-08-06 那条）
- 分支源码: https://github.com/anatoli-tsinovoy/oh-my-pi/tree/termux-android-arm64
