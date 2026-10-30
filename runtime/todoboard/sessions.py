"""Native OV sessions; receipts survive every asynchronous boundary."""
import json,urllib.parse
from .models import stable_id
from .store import atomic_json

def capture_session(p,event,publish=True,memory_types=None):
    key=event['id'];previous=p.ledger.get('session:'+event['sessionID'],0)
    messages=event['messages'][previous:]
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
    if publish:atomic_json(p.root/'inbox'/f'commit-{key}.json',{'version':1,'id':'commit-'+key,'kind':'ov-commit','receipt':receipt,'title':'Codex session'})
    p.ledger.put('session:'+event['sessionID'],len(event['messages']))


def archive_submission(p,event):
    receipt=event['receipt'];sid=receipt['session_id'];archive=receipt['archive_uri'].rstrip('/').rsplit('/',1)[-1]
    data=p.ov.request('GET',f'/api/v1/sessions/{urllib.parse.quote(sid,safe="")}/archives/{urllib.parse.quote(archive,safe="")}')
    messages=data.get('messages',[])
    if not messages:raise RuntimeError('archive not ready')
    # Only completed archive reads can trigger automatic candidate extraction.
    content=json.dumps(messages,ensure_ascii=False,indent=2)
    p.submit(receipt['archive_uri'],'codex-session',event.get('title','Agent session'),content,source_uri=receipt['archive_uri'])
    p.ledger.put('commit:'+event['id'],receipt)
