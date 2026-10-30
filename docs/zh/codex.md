# Codex CLI、GUI 与原生 harness

Board 只分发。Codex 负责执行、对话、Skills、工具、MCP、审批和沙箱。工作目录是执行位置，不是额外的能力隔离：Codex 全局配置中的能力仍可能可见。

## CLI 后台执行

`defaultAgent.adapter: codex-cli` 时，Board 将请求写入持久队列，后台调用 `codex exec --json -C <workspace>`。关闭 Board 后，LaunchAgent 继续执行并保存轨迹。结果回写 `execution`，用户在 Board 完成卡片。

CLI 的非交互执行使用 Codex 自身的策略。需要交互审批或对话的任务应交给 GUI，或回传 `needsInput`。TodoBoard 不添加跳过审批的参数。可通过 Agent 配置选择模型与入口。

## GUI 桌面交接

`codex-gui` 通过本地 App Server 创建持久 thread，结束临时服务器，再在未加载 thread 的服务器中调用 `thread/queue/list`、`thread/read` 和 `thread/queue/add`。随后 App 打开 Codex deep link，由桌面应用接管执行。

不能在临时 App Server 启动回合后立刻退出；那会把执行生命周期留在临时进程里。这里保存的是真实 thread / submission 回执，并按 request ID 检查已排队和已消费输入，避免重发。

队列 API 是实验能力。当前已验证的客户端版本见 `config/versions.json`；运行时调用真实接口检查，不支持就报错并保留输入，不能显示投递成功。CLI 是独立适配选项，不在失败时偷偷替换。

## Hooks 与 MCP

安装后台后，数据目录的 `integrations/codex/` 生成 `hooks.json`、`hook.sh` 与 `mcp.json` 模板，不会自动改全局配置。按[官方 Codex 插件文档](https://developers.openai.com/plugins/build/plugins)把 Hook 加入本地插件，通过 Codex 的正常信任流程启用。命令必须引用生成的 `hook.sh`，以保留数据目录与模块路径。

在 `sources.codexWorkspaces` 显式列出允许留存对话的工作区。Stop Hook 只写本地收件箱，网络、归档与模型处理放在后台。Hook 不依赖关闭窗口，也不会把工具参数和结果复制成对话记忆。

把生成的 MCP 设置加入自己的 Codex 配置；stdio 命令是后台 venv 的 Python，参数 `-m todoboard.mcp`，环境包括同一 `TODOBOARD_DATA_DIR` 与 `PYTHONPATH`。可复制 `integrations/codex/skills/todoboard/` 作为可选技能。

`knowledge_read` / `knowledge_search` 供按需取背景；`submit_todo` 用于明确记录；`agent_event` 用于结果和阻塞。配置引用是声明，是否真的加载以 Codex 的能力列表和执行结果为准。

## 一起使用

可以在 CLI 发起后台任务，在 Codex GUI 继续一个持久 thread；具体恢复方式取决于该版本 Codex 的原生功能。TodoBoard 会保存 thread ID，不能保证任意 CLI 会话都能通过实验队列无缝接续。GUI 专用线程由桌面执行；结果监听只读线程，不擅自 resume 或启动回合。

选中工作区时，Board 用 macOS 原生目录选择器保存授权书签，并在投递期间保持访问。执行器自己的文件权限与审批仍需正常通过。
