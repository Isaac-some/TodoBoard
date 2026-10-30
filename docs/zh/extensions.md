# Agent 与知识库扩展

Agent 由角色说明和实际执行入口组成。CLI 还是 GUI 由适配器决定；Board 不要求其他产品模仿 Codex 的 App Server。

设置 `agents.<id>.adapter: command` 并提供参数数组 `command`。后台从标准输入提交一个版本化 JSON 任务包。适配器返回 JSON 回执：`submissionID`、可选 `threadID`、`state`，之后用事件接口回传进度、结果及证据。命令不经过 shell 字符串插值。

```json
{"adapter":"command","command":["/absolute/path/to/agent-adapter","submit"],"timeoutSeconds":120}
```

适配器应保存 request ID 并去重，说明 CLI / GUI 的生命周期以及审批发生在哪里。Trae、zcode、qoder、workbuddy、Hermes 等可实现相同协议；仓库不声称已经验证它们。

知识库设置 `provider: command`、`command` 和 `capabilities: ["read","write","search"]`。stdin 为 `{version:1, operation, ...parameters}`；stdout 为 `{version:1, result}`。不支持的能力必须明确失败，不得伪造成功。支持 Session 的后端可以另行实现采集提交接口；不支持 Session 时仍可接收归档文字资料。

新适配器需要验证重复提交、结果不明、重启恢复和资料不可用的情况。参见 [协议](./protocols) 与 `examples/command-adapter.py`。
