"""Record relocatable developer installation; produce opt-in integration templates."""
import json,sys,os
from pathlib import Path
from .config import initialize
from .store import atomic_json

def main():
    root=initialize(None);module=Path(__file__).resolve().parents[1]
    atomic_json(root/'runtime-install.json',{'python':sys.executable,'modulePath':str(module)})
    command=f'"{sys.executable}" -m todoboard.hook'
    # No edits to global Codex config, plugin state, Skills or existing captures.
    atomic_json(root/'integrations/codex/hooks.json',{'hooks':{'Stop':[{'hooks':[{'type':'command','command':command,'timeout':10}]}]}})
    atomic_json(root/'integrations/codex/mcp.json',{'mcpServers':{'todoboard':{'command':sys.executable,'args':['-m','todoboard.mcp'],'env':{'TODOBOARD_DATA_DIR':str(root),'PYTHONPATH':str(module)}}}})
    wrapper=root/'integrations/codex/hook.sh'
    import shlex
    wrapper.write_text('#!/bin/sh\nexport TODOBOARD_DATA_DIR='+shlex.quote(str(root))+'\nexport PYTHONPATH='+shlex.quote(str(module))+'\nexec '+shlex.quote(sys.executable)+' -m todoboard.hook\n');wrapper.chmod(0o700)
    hooks={'hooks':{'Stop':[{'hooks':[{'type':'command','command':shlex.quote(str(wrapper)),'timeout':10}]}]}}
    atomic_json(root/'integrations/codex/hooks.json',hooks)
    print(json.dumps({'dataDir':str(root),'state':'installed','backgroundStarted':False,'hooksEnabled':False}))

if __name__=='__main__':main()
