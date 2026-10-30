# 配置

`config/config.example.json` 是完整空配置模板。运行时只读取数据目录的 `config.json`。初始化不会扫描个人目录，也不会启用飞书。

| 配置 | 用途 |
|---|---|
| `sources.directories` | 允许后台读取的本地文字目录 |
| `sources.codexWorkspaces` | 允许 Stop Hook 留存对话的项目目录及其子目录 |
| `sources.feishu.enabled` | 开启当前 CLI 用户身份下的会议、妙记读取 |
| `sources.feishu.cliPath / profile` | 官方飞书 CLI 入口和可选账号配置 |
| `sources.feishu.initialLookbackDays` | 首次读取范围；之后按已覆盖游标补查 |
| `knowledge.enabled / provider` | 是否启用知识库；`openviking` 或 `command` |
| `knowledge.configFile` | 独立 OV 客户端配置文件；后台和 MCP 共用 |
| `knowledge.resourceRoot / searchRoot` | 归档位置与补充检索范围 |
| `extraction.enabled / executable / model` | 是否由 Codex 从成功归档的原文识别行动项 |
| `defaultAgent` | 默认适配器和可执行入口 |
| `agents.<Agent ID>` | 某个 Agent 的适配器、模型、入口等覆盖配置 |

Agent ID 来自数据目录的 `agent-workspace.json`。看板里配置角色、Skills、工具、MCP 与知识库说明；真实加载和授权仍由执行器自身完成。后台 `agents` 用同一 ID 关联实际执行入口。例如：

```json
{"defaultAgent":{"adapter":"codex-gui","executable":"/path/to/codex"},"agents":{"example-agent-id":{"adapter":"codex-cli","executable":"/path/to/codex","model":"your-model"}}}
```

这是部分配置示意，应合并到完整文件，不要用它覆盖全部配置。可执行路径建议用绝对路径，因为 LaunchAgent 的环境可能与交互式终端不同。

凭据保存在用户自己的 OV / 飞书配置中，仓库只包含模板。多个实例通过 `TODOBOARD_DATA_DIR` 分开，Hook、App 和后台必须使用同一个值。
