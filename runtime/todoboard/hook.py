"""Codex Stop capture: opt-in by workspace; no network or model work in the hook."""
import json, os, sys, uuid
from pathlib import Path
from .config import data_root, load
from .store import atomic_json
from .models import stable_id

def capture(value,root):
    if os.getenv('TODOBOARD_INTERNAL')=='1':return
    config=load(root);cwd=Path(value.get('cwd','/')).expanduser().resolve()
    allowed=[Path(x).expanduser().resolve() for x in config['sources'].get('codexWorkspaces',[])]
    if not any(cwd==x or cwd.is_relative_to(x) for x in allowed):return
    transcript=Path(value.get('transcript_path',''))
    if not transcript.is_file():return
    messages=[]
    for line in transcript.read_text().splitlines():
        try:
            item=json.loads(line);payload=item.get('payload',{})
            if item.get('type')!='response_item' or payload.get('type')!='message' or payload.get('role') not in {'user','assistant'}:continue
            if payload.get('phase')=='commentary':continue
            text='\n'.join(x.get('text','') for x in payload.get('content',[]) if x.get('type') in {'input_text','output_text','text'})
            if not text or '<environment_context>'in text or '<system_reminder>'in text:continue
            # Tools and system prompts are intentionally excluded from session material.
            messages.append({'role':payload['role'],'content':text,'created_at':item.get('timestamp')})
        except (ValueError,TypeError):continue
    if not messages:return
    session=value.get('session_id','unknown');identity=stable_id('capture',session,json.dumps(messages,ensure_ascii=False))
    atomic_json(root/'inbox'/f'{identity}.json',{'version':1,'id':identity,'kind':'codex-capture','sessionID':session,'cwd':str(cwd),'messages':messages,'summary':value.get('last_assistant_message','')})

def main():
    try:capture(json.load(sys.stdin),data_root())
    except Exception as e:
        # A capture failure must not prevent the agent from finishing its turn.
        print('TodoBoard capture unavailable: '+type(e).__name__,file=sys.stderr)

if __name__=='__main__':main()
