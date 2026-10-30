# 资料留存

后台保存原文，卡片保存位置。每次资料提交生成内容哈希，并在 `materials/<source-version>/` 保存 `original.md`、`metadata.json` 和成功归档凭据。同一来源的不同内容版本可追溯；不会把运行资料放入源码仓库。

首次运行没有采集范围。需要本地文字采集时，在 `sources.directories` 中逐个列出允许读取的目录。后台支持 `.md`、`.txt`、`.srt`、`.json`，跳过符号链接及大于 10 MB 的文件。不要把整个 home 或源码根目录作为文字资料目录。

一次性导入不需要启用目录扫描：

```bash
cd ~/Projects/TodoBoard
.venv/bin/todoboardctl source examples/meeting.md --kind local --id synthetic-meeting --observed-at '2026-10-30T09:00:00+08:00'
.venv/bin/todoboardctl run-once
```

导入先留存在本地。只有知识库归档成功后，自动行动项识别才会运行；模型不可用或 OV 离线时，资料和队列仍保留。显式提供 `--actions-file examples/actions.json` 可复现有证据的结构化提交。

Codex 的 Stop Hook 仅处理显式允许的项目，读取本次会话中的用户与最终助手消息，排除系统和工具消息，并先写入本地 inbox。后台通过原生 OV Session 追加消息、commit、保存凭据，再等归档可读。不会把关闭聊天窗口当作会话提交信号。

飞书采集使用官方 CLI、用户身份及所选 profile。按窗口分页读取，保留未覆盖范围，休眠恢复后从成功游标补查；缺权限或逐字稿暂不可读时不会把该时间段标记成成功。详见 [权限矩阵](./feishu)。
