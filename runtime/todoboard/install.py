"""Generate an opt-in local Codex marketplace without editing existing agent config."""
import json,sys,shlex,shutil
from pathlib import Path
from .config import initialize
from .store import atomic_json

def main():
    root=initialize(None);module=Path(__file__).resolve().parents[1]
    atomic_json(root/'runtime-install.json',{'python':sys.executable,'modulePath':str(module)})
    market=root/'integrations/codex';plugin=market/'plugin';plugin.mkdir(parents=True,exist_ok=True)
    hooks={}
    for event,name in [('Stop','hook'),('UserPromptSubmit','recall')]:
        wrapper=plugin/f'{name}.sh'
        wrapper.write_text('#!/bin/sh\nexport TODOBOARD_DATA_DIR='+shlex.quote(str(root))+'\nexport PYTHONPATH='+shlex.quote(str(module))+'\nexec '+shlex.quote(sys.executable)+' -m todoboard.'+name+'\n');wrapper.chmod(0o700)
        hooks[event]=[{'matcher':'*','hooks':[{'type':'command','command':'sh "${PLUGIN_ROOT}/'+name+'.sh"','timeout':10}]}]
    atomic_json(plugin/'hooks/hooks.json',{'hooks':hooks})
    atomic_json(plugin/'.codex-plugin/plugin.json',{'name':'todoboard','version':'0.1.0','description':'Scoped TodoBoard memory retrieval, session retention and task result integration.','author':{'name':'TodoBoard contributors'},'license':'MIT','repository':'https://github.com/Isaac-some/TodoBoard','hooks':'./hooks/hooks.json','mcpServers':'./.mcp.json','skills':'./skills/'})
    mcp={'mcpServers':{'todoboard':{'command':sys.executable,'args':['-m','todoboard.mcp'],'env':{'TODOBOARD_DATA_DIR':str(root),'PYTHONPATH':str(module)}}}}
    atomic_json(plugin/'.mcp.json',mcp);atomic_json(market/'mcp.json',mcp)
    atomic_json(market/'hooks.json',{'hooks':hooks})
    skill=module.parent/'integrations/codex/skills/todoboard/SKILL.md'
    if skill.is_file():
        target=plugin/'skills/todoboard';target.mkdir(parents=True,exist_ok=True);shutil.copy2(skill,target/'SKILL.md')
    atomic_json(market/'.agents/plugins/marketplace.json',{'name':'todoboard-local','interface':{'displayName':'TodoBoard local integration'},'plugins':[{'name':'todoboard','source':{'source':'local','path':'./plugin'},'policy':{'installation':'AVAILABLE','authentication':'ON_INSTALL'},'category':'Productivity'}]})
    print(json.dumps({'dataDir':str(root),'state':'installed','marketplace':str(market),'backgroundStarted':False,'hooksEnabled':False}))

if __name__=='__main__':main()
