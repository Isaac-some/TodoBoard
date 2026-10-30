# OpenViking

本项目使用火山引擎官方 **OpenViking 0.5.2.1**，核对日期为 2026-10-30。这是当时 GitHub 与 PyPI 的最新稳定版。服务器保持原版，无旧环境补丁、私人记忆规则或个人账号。版本锁见 `config/versions.json`。

你可以连接自己部署的官方 OV，也可以使用兼容的托管服务。服务地址、凭据、资料归档位置和检索范围都由你配置。TodoBoard 不迁移已有知识库。

独立环境安装：

```bash
cd ~/Projects/TodoBoard
python3 -m venv .ov-venv
.ov-venv/bin/python -m pip install -r requirements-openviking.txt
export OPENVIKING_CONFIG_FILE="$PWD/.runtime/ov/ov.conf"
.ov-venv/bin/openviking-server init
.ov-venv/bin/openviking-server --config "$OPENVIKING_CONFIG_FILE"
```

初始化向导需要选择模型服务、VLM 与 embedding，并配置独立数据目录。OV 的记忆抽取和语义检索需要相应模型；不因为安装了 Codex 就自动获得 embedding。按[官方配置文档](https://docs.openviking.ai/zh/guides/01-configuration)完成模型与服务部署。已有 OV 用户请使用独立配置路径，避免向导覆盖自己的配置。

创建只属于此部署的客户端配置，例如 `~/.config/todoboard/ovcli.conf`：

```json
{"url":"http://127.0.0.1:1934","api_key":"YOUR_USER_KEY"}
```

把 `knowledge.configFile` 指向它，设置 `knowledge.enabled: true`。需要账号身份头的部署可配置 `account`、`user`、`actor_peer_id`；普通用户 API key 按服务的身份机制使用，不把 root key 交给日常 Agent。

需要验收后的原生经验提取时，在服务端独立 `ov.conf` 启用 `"agent_evolution":{"enabled":true}`。0.5.2.1 默认关闭此能力；成功提交会话仍可能提取零条经验。TodoBoard 对验收结果使用官方 `cases → trajectories → experiences` 链路，普通会话留存仅抽取用户资料类记忆，不提前训练执行经验。经验位于对应 Agent 的命名空间；将需要的 `viking://agent/<agent-id>/memories/experiences` 纳入实际检索配置。验收资源始终保存在 `knowledge.resourceRoot/accepted/`，可以独立检索。

`todoboardctl status` 的 `memoryTasks` 单独报告异步提取状态、提取数量和跳过原因。`jobs` 完成表示后台已处理该投递步骤，不代表模型一定产生了经验。模型授权失效时先修复自己的服务配置，保留资料和回执后检查原生任务；不要反复复制同一个会话冒充成功。

后台使用原生 content write/read、find、sessions、archives 和任务状态接口。Session commit 的 Phase 1 归档先完成，Phase 2 记忆提取异步运行。成功收到 HTTP 响应不等于经验已经可检索。后台保留原始 commit 凭据，等待归档接口真正可读后才识别候选。

Hook 与 MCP 都使用同一数据目录和配置。官方 OV 记忆插件可独立安装并锁定官方发布版本；如果同时使用它采集同一会话，应关闭 TodoBoard 对这些工作区的重复捕获。TodoBoard 的 Hook 不修改官方 OV 插件。

升级时修改版本锁，在新数据目录验证官方 API、模型与归档流程后再发布。运行时 `doctor` 检查服务版本；不悄悄升级服务器。
