# 快速开始

面向能配置环境的开发者。看板支持 macOS 13+；本机安装官方 OV wheel 时，Apple Silicon 需要 macOS 14+、Intel 需要 macOS 15+。也可以连接远端 OV，Mac 只运行 Board 和后台。

先安装 Xcode Command Line Tools、Python 3.10+、Node.js 20+。Codex 按官方安装方式安装并登录；其可执行文件必须能被后台找到。

```bash
cd ~/Projects
git clone https://github.com/Isaac-some/TodoBoard.git
cd TodoBoard
PYTHON_BIN=python3 ./scripts/install-runtime.sh
.venv/bin/todoboardctl init
.venv/bin/todoboardctl doctor
```

macOS 自带 Python 可能过旧；此时把 `PYTHON_BIN` 换成你安装的 Python 3.10+ 完整路径。安装器只创建本仓库 `.venv`，并写入新的独立数据目录，不修改全局 Codex 或 OV 配置。

默认数据目录为 `~/Library/Application Support/TodoBoard-OpenSource`。需要独立测试时，在所有命令及启动 App 前设置同一个 `TODOBOARD_DATA_DIR`。不要指向已有个人看板目录。

```bash
cd ~/Projects/TodoBoard
export TODOBOARD_DATA_DIR="$PWD/.runtime/demo"
.venv/bin/python -m todoboard.install
.venv/bin/todoboardctl init
.venv/bin/todoboardctl submit-todo '验证这套工作流' --notes '这是一条合成示例'
.venv/bin/todoboardctl start
./scripts/build-app.sh
open dist/TodoBoard.app
```

Release 中也提供已构建的 Mac App；后台通过同版本源码的安装脚本安装。App 使用 ad-hoc 签名，尚无 Developer ID 公证，首次打开按 macOS 本地应用流程操作。

打开 Board 后，把候选拖入待办，选择 Agent 和工作文件夹，再点击分发。默认使用 Codex GUI；要用 CLI，在数据目录的 `config.json` 把 `defaultAgent.adapter` 改为 `codex-cli`。CLI 在后台运行，GUI 通过桌面应用继续执行。

启用记忆和自动候选之前，先完成 [OV 配置](./openviking)、[来源配置](./sources) 和 [Codex Hooks](./codex)。空配置下，主动 Todo 可以使用；资料先保存在本地，等待知识库启用后补归档。
