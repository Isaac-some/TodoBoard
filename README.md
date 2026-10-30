# TodoBoard

A native macOS task board connecting work materials, personal memory and your agent's own harness.

**Retain materials → archive in OpenViking → review Todo candidates → dispatch to an agent → receive results → accept manually → retain reusable evidence.**

[中文开发者文档](https://isaac-some.github.io/TodoBoard/) · [Architecture and route](https://isaac-some.github.io/TodoBoard/zh/architecture) · [Releases](https://github.com/Isaac-some/TodoBoard/releases)

The Board is the product's only UI. A separate background worker handles collection, provenance, retrieval, durable delivery and result tracking. Conversations, Skills, tools, MCP, sandboxing and approvals remain in the agent's own runtime. Codex CLI and GUI are the first adapters; other agents and knowledge stores can implement versioned command protocols.

An empty installation collects **nothing**. Sources (local text directories, selected Codex workspaces, Feishu meetings) are explicitly configured. Personal memories, meetings, tasks, identities, credentials, role configurations and execution logs are excluded from this repository and its history. Existing personal installations are preserved.

## Quick start

Requires macOS 13+, Xcode command line tools, Python 3.10+ and a separately installed/authenticated Codex. A remote knowledge service is supported. The optional official OpenViking local wheel has its own platform requirements.

```bash
cd ~/Projects
git clone https://github.com/Isaac-some/TodoBoard.git
cd TodoBoard
PYTHON_BIN=python3 ./scripts/install-runtime.sh
.venv/bin/todoboardctl init
.venv/bin/todoboardctl submit-todo 'Verify this workflow' --notes 'Synthetic example'
.venv/bin/todoboardctl start
./scripts/build-app.sh
open dist/TodoBoard.app
```

Default data: `~/Library/Application Support/TodoBoard-OpenSource`. Override `TODOBOARD_DATA_DIR` consistently for the App, worker, hooks and MCP. Configure `config.json` there; start from `config/config.example.json`. The installer generates opt-in Codex integration templates without editing your global configuration.

Knowledge defaults to disabled. This release targets **official, unmodified OpenViking 0.5.2.1**, the latest stable release checked on 2026-10-30. Choose your service URL, user credentials, models and retrieval locations. No patches from the author's former installation are included. Feishu uses official `@larksuite/cli` 1.0.98 and your own authorization.

CLI tasks run in the durable worker. GUI tasks use experimental App Server queue APIs and require a compatible Codex desktop app. Unsupported APIs fail explicitly while preserving input. Delivery receipts and execution results never mark a card complete; the user does that in the Board.

## Development

```bash
cd ~/Projects/TodoBoard
swift test --scratch-path .build-local
PYTHONPATH=runtime .venv/bin/python -m unittest discover -s Tests -v
npm ci
npm run docs:build
.venv/bin/python scripts/check-publication.py
```

`tasks.json` is the sole card source. Swift and Python share a cross-process file lock, re-read before saving and atomically replace JSON. The SQLite ledger stores progress and execution records, not a second card database.

The Mac app is ad-hoc signed; Developer ID signing and notarization are not claimed. The runtime, Python and external agent / OV services are installed separately. See the documentation for deployment, failure recovery, permissions and validation limits.

MIT for TodoBoard. External OpenViking remains AGPL-3.0; see [third-party notices](THIRD_PARTY_NOTICES.md).
