# AGENTS

## 项目约定

- GitHub Actions 工作流仅手动触发，仅上传编译好的 `.node` 作为 artifact；不打包 npm 包、不安装、不发布 release。
- 只保留仓库根目录的 `patch.sh` 作为安装脚本；不要新增第二个安装脚本。

## patch.sh

- 保持最小化：不备份、不回滚、不做 smoke 测试、不输出过程信息；只保留安全校验与安装动作。
- 必须先 `cd "$(dirname "$0")"`，保证从任意目录调用时都以仓库根目录为基准。
- 保留 `if` 形式的安全判断：`omp` 必须存在，解析后的 `omp` 路径必须包含 `/.bun/install/global/`，平台必须是 Android，必须能从该 CLI 解析到已安装的 `@oh-my-pi/pi-natives`，addon 与三个 JS 源文件必须存在，已安装 natives 版本必须等于 addon 的 `__piNativesBuildVersion()`。
- 失败时只输出一行错误并非零退出。

## 文档

- README 保持简短，只说明工作流产物、触发方式、`patch.sh` 用法和 AGENTS.md 位置；提示与约定写在本文件，不写入 README。
