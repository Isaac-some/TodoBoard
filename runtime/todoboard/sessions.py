"""Native OV sessions; receipts survive every asynchronous boundary."""
import json,urllib.parse,hashlib
from .models import stable_id
from .store import atomic_json

def capture_session(p,event,publish=True,memory_types=None):
    # Ordinary conversation retention must not promote unaccepted executions into
    # reusable agent experience. OV 0.5.2.1 trains experience through cases/trajectories.
    if memory_types is None:memory_types=['entities','events','identity','preferences','profile','soul']
    key=event['id'];seen_key='session-seen:'+event['sessionID'];seen=p.ledger.get(seen_key,[])
    # A compacted transcript can shrink or replace its prefix; a positional cursor loses turns.
    occurrences={};fingerprints=[];messages=[]
    for message in event['messages']:
        digest=hashlib.sha256(json.dumps(message,sort_keys=True,ensure_ascii=False).encode()).hexdigest()
        occurrences[digest]=occurrences.get(digest,0)+1
        fingerprint=digest+':'+str(occurrences[digest]);fingerprints.append(fingerprint)
        if fingerprint not in seen:messages.append(message)
    if not messages:return
    if not p.config['knowledge']['enabled']:raise RuntimeError('knowledge disabled; captured turn retained')
    # One immutable native session per captured batch avoids re-sending old turns.
    sid=stable_id('todoboard',key);state=p.ledger.get('capture:'+key,{})
    if not state.get('created'):
        try:p.ov.request('POST','/api/v1/sessions',{'session_id':sid,'memory_policy':{'memory_types':memory_types}} if memory_types else {'session_id':sid})
        except RuntimeError as e:
            if 'HTTP 409' not in str(e):raise
            p.ov.request('GET','/api/v1/sessions/'+sid)
        state['created']=True;p.ledger.put('capture:'+key,state)
    if state.get('appendStarted') and not state.get('appended'):
        raise RuntimeError('OV message append outcome uncertain; inspect session before retrying')
    if not state.get('appended'):
        state['appendStarted']=True;p.ledger.put('capture:'+key,state)
        for index in range(0,len(messages),100):
            p.ov.request('POST',f'/api/v1/sessions/{sid}/messages/batch',{'messages':messages[index:index+100]})
        state['appended']=True;p.ledger.put('capture:'+key,state)
    if not state.get('receipt'):
        receipt=p.ov.request('POST',f'/api/v1/sessions/{sid}/commit',{})
        if not receipt.get('archived') or not receipt.get('archive_uri'):raise RuntimeError('OV did not confirm archival')
        state['receipt']=receipt;p.ledger.put('capture:'+key,state)
    receipt=state['receipt']
    if receipt.get('task_id'):
        task_key='memory-task:'+receipt['task_id']
        if not p.ledger.get(task_key):p.ledger.put(task_key,{'taskID':receipt['task_id'],'sessionID':sid,'archiveURI':receipt['archive_uri'],'state':'pending'})
    if publish:atomic_json(p.root/'inbox'/f'commit-{key}.json',{'version':1,'id':'commit-'+key,'kind':'ov-commit','receipt':receipt,'title':'Codex session'})
    p.ledger.put(seen_key,list(dict.fromkeys(seen+fingerprints)))
    p.ledger.put('session:'+event['sessionID'],len(event['messages']))

def poll_commit_tasks(p):
    if not p.config['knowledge']['enabled'] or 'sessions' not in getattr(p.ov,'capabilities',set()):return
    for row in p.ledger.db.execute("SELECT id,value FROM kv WHERE id LIKE 'memory-task:%'").fetchall():
        value=json.loads(row['value'])
        if value['state'] in {'completed','failed','cancelled'}:continue
        try:
            result=p.ov.request('GET','/api/v1/tasks/'+value['taskID'])
            details=result.get('result') or {}
            value.update(state=result['status'],stage=result.get('stage'),error=result.get('error'),memoriesExtracted=details.get('memories_extracted'),skipReason=details.get('agent_memory_skip_reason'))
            p.ledger.put(row['id'],value)
        except Exception:pass


def archive_submission(p,event):
    receipt=event['receipt'];sid=receipt['session_id'];archive=receipt['archive_uri'].rstrip('/').rsplit('/',1)[-1]
    data=p.ov.request('GET',f'/api/v1/sessions/{urllib.parse.quote(sid,safe="")}/archives/{urllib.parse.quote(archive,safe="")}')
    messages=data.get('messages',[])
    if not messages:raise RuntimeError('archive not ready')
    # Only completed archive reads can trigger automatic candidate extraction.
    content=json.dumps(messages,ensure_ascii=False,indent=2)
    p.submit(receipt['archive_uri'],'codex-session',event.get('title','Agent session'),content,source_uri=receipt['archive_uri'])
    p.ledger.put('commit:'+event['id'],receipt)
