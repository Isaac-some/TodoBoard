# 构建与发布

源码白名单只包含应用、后台、测试、脚本、配置模板、合成示例、文档与构建配置。现有工程和个人运行目录没有加入 Git 历史。

```bash
cd ~/Projects/TodoBoard
swift test --scratch-path .build-local
PYTHONPATH=runtime .venv/bin/python -m unittest discover -s Tests -v
npm ci
npm run docs:build
./scripts/build-app.sh
.venv/bin/python scripts/check-publication.py
```

构建脚本生成 arm64 / x86_64 通用应用和 zip。App 内包含同版本 Python 源码与安装说明，Python 解释器和官方 OV / 飞书 / Codex 依赖由开发者独立安装。Release 同时发布辅助源码包与 SHA-256，便于从 tag 复现。

本版 ad-hoc 签名，不宣称已公证。使用 Developer ID 的维护者可在自己的 CI 密钥环境完成签名与公证，不把证书、Apple 凭据放入仓库。

Pages 工作流构建 VitePress 并部署到 GitHub Pages。Release 工作流在 tag 上构建 Mac App。发布之前检查工作树、待提交文件、Git 对象和分发包；运行资料、记忆、会议、角色配置、凭据、日志、截图与历史构建产物均不应出现。
