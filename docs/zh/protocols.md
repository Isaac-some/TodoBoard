# 版本化协议

三类协议都要求 `version: 1`，不支持的版本明确失败。可执行规范见 `schemas/`；Python 模块的职责是验证并持久化，不把整块 Board 交给外部执行器覆盖。

| 接口 | 必填 | 行为 |
|---|---|---|
| 资料提交 | `source_id, kind, title, content` | 先留存原文及版本，再排队归档 |
| 知识库适配 | `operation`、该操作的参数 | read / write / search；能力由适配器声明 |
| Agent 任务 | `requestID, cwd, prompt, taskIDs` | 关联卡片、资料背景、角色说明与补充要求 |
| Agent 事件 | `event_id, task_id, state` | 去重，记录结果；不修改正式状态 |

资料通过 `todoboardctl source-json FILE` 提交。可选 `observed_at`、`source_uri`、`actions`。actions 的每项包含 `title`、`evidence`、可选 `locator`；证据必须是原文的真实子串。

分发通过 `todoboardctl handoff --packet-file FILE`。`taskIDs` 可以是多张卡片，`agentID` 关联配置，`instructions` 为角色指令，`prompt` 为目标和补充说明。后台将带来源的检索背景附加到任务包。

事件通过 `todoboardctl event FILE` 或 MCP `agent_event`。state 支持 `received`（映射 queued）、`running`、`needsInput`、`result`、`failed`；可选 `summary`、`evidence` 字符串数组、`agent_id`、`adapter`。同一 `event_id` 重复处理不产生新事件。

投递回执与任务结果是两条记录。未知执行结果应保留请求并要求核对；不能自动用新 ID 再执行有外部影响的任务。
