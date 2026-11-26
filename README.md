# oh-my-pi Termux/Android arm64

GitHub Actions 工作流手动触发（`workflow_dispatch`），可指定上游 `upstream_ref`（默认 `v19.2.1`），只产出编译好的 `pi_natives.android-arm64.node` 作为 Actions artifact。

下载 artifact 中的 `.node` 文件后运行：

```bash
./patch.sh <下载的 .node>
```

仓库开发指引见 [AGENTS.md](AGENTS.md)。
