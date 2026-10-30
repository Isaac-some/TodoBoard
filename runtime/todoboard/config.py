"""One explicit configuration, shared by hooks, worker and app handoff."""
import json, os
from pathlib import Path

DEFAULT_DATA = Path.home() / 'Library/Application Support/TodoBoard-OpenSource'

def data_root(value=None):
    return Path(value or os.environ.get('TODOBOARD_DATA_DIR', DEFAULT_DATA)).expanduser().resolve()

def defaults():
    return {'version': 1, 'sources': {'directories': [], 'codexWorkspaces': [], 'feishu': {'enabled': False, 'cliPath': 'lark-cli', 'initialLookbackDays': 7, 'intervalMinutes': 20}},
            'knowledge': {'provider': 'openviking', 'configFile': '~/.config/todoboard/ovcli.conf', 'resourceRoot': 'viking://resources/todoboard',
                          'searchRoot': 'viking://resources', 'enabled': False},
            'agents': {}, 'defaultAgent': {'adapter': 'codex-gui', 'executable': 'codex'},
            'extraction': {'enabled': False, 'executable': 'codex', 'model': None}, 'pollSeconds': 60}

def load(root):
    path = Path(root)/'config.json'
    return json.loads(path.read_text()) if path.exists() else defaults()

def initialize(root):
    from .store import atomic_json
    root = data_root(root); root.mkdir(parents=True, exist_ok=True)
    if not (root/'config.json').exists(): atomic_json(root/'config.json', defaults())
    os.chmod(root, 0o700)
    return root
