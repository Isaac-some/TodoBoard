#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
PYTHON_BIN="${PYTHON_BIN:-python3}"
"$PYTHON_BIN" -c 'import sys; assert sys.version_info >= (3,10), "Python 3.10+ required; set PYTHON_BIN"'
"$PYTHON_BIN" -m venv .venv
.venv/bin/python -m pip install --disable-pip-version-check -e .
.venv/bin/python -m todoboard.install
