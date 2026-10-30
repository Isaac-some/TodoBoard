#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist
tar --exclude='__pycache__' --exclude='*.pyc' -czf dist/TodoBoard-runtime.tar.gz \
  runtime integrations config examples pyproject.toml README.md LICENSE THIRD_PARTY_NOTICES.md \
  requirements-openviking.txt scripts/install-runtime.sh
