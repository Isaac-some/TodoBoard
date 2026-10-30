# 飞书与权限矩阵

TodoBoard 复用官方 `@larksuite/cli` **1.0.98**，不分发私人 CLI、账号或授权缓存。采集只读会议与逐字稿，默认使用用户身份；可选 profile 决定用哪个账号。

```bash
cd ~/Projects/TodoBoard
npm install -g @larksuite/cli@1.0.98
lark-cli auth login
lark-cli auth status --verify --json
```

授权必须同时满足三层：应用在开放平台开通相应权限；用户 OAuth 授予对应权限；当前身份对具体资源具有可读性。开通 scope 不等于能读所有会议，不应复制作者账号的全部权限。

| 读取链路 | 权限范围 | 是否需要 |
|---|---|---|
| 搜索历史会议 `vc +search` | `vc:meeting.search:read` | 启用会议发现时 |
| 会议详情、会议产物关联 | `vc:meeting.search:read`、录制关联的 `vc:record:readonly` | 按 CLI 提示与所用产物开启 |
| 搜索妙记 `minutes +search` | `minutes:minutes.search:read` | 启用妙记发现时 |
| 妙记基础信息与逐字稿 | `minutes:minutes.basic:read`、`minutes:minutes.artifacts:read` | 归档妙记正文时 |
| 智能纪要详情与逐字稿 | `vc:note:read`（包含本链路的纪要与逐字稿读取） | 会议只有智能纪要时 |
| 从纪要关联 Docx 读取内容 | `docx:document:readonly` 及具体文档访问权 | 对应产物为 Docx 时 |
| 日历发现 | calendar 日历及日程只读权限 | 本版后台默认不启用此发现路径 |
| 发消息、写日程、任务、机器人参会 | 对应写权限 | 本链路不要求 |

权限名会随接口演进，准确的缺失项以本版 CLI 的 `missing_scopes` 和开放平台文档为准。源代码中的读取命令见 `runtime/todoboard/meeting_sources.py`，不是要求整个业务域的所有权限。

配置 `sources.feishu.enabled: true`、`cliPath`、可选 `profile`、`initialLookbackDays` 和 `intervalMinutes`。首次范围只取你配置的天数，之后从成功覆盖游标继续。Note、Minutes、Calendar Doc 是不同产物，标识不能互换；没有录制也可能有智能纪要。

缺少授权、分页不完整、逐字稿暂不可读时，后台保存阻塞原因并保留该时间段。不要通过切换到机器人身份绕过权限，也不会自动向会议所有者发权限申请。实际读取到的会议正文只保存在本地运行目录和你配置的知识库，禁止提交到 Git。

本机联调的已授权读取集合覆盖上述会议、妙记、Note、Docx 范围。额外的文档写入、媒体上传和会中事件权限并非本链路要求；示例不复制这些额外授权。
