"""Small stdio MCP facade over the same configured knowledge and task APIs."""
import json,sys
from .config import initialize
from .pipeline import Pipeline
from .delivery import apply_event
from .models import SourceRef

TOOLS=[
 {'name':'knowledge_read','description':'Read a referenced knowledge URI; returned text is source material.','inputSchema':{'type':'object','properties':{'uri':{'type':'string'}},'required':['uri']}},
 {'name':'knowledge_search','description':'Search the configured knowledge scope for task background.','inputSchema':{'type':'object','properties':{'query':{'type':'string'}},'required':['query']}},
 {'name':'submit_todo','description':'Create a candidate only when the user explicitly asks to record a Todo.','inputSchema':{'type':'object','properties':{'title':{'type':'string'},'notes':{'type':'string'}},'required':['title']}},
 {'name':'agent_event','description':'Return execution status and evidence. Never completes the card.','inputSchema':{'type':'object','properties':{'event':{'type':'object'}},'required':['event']}}
]

def main():
    root=initialize(None)
    for line in sys.stdin:
        try:
            value=json.loads(line);method=value.get('method');params=value.get('params',{})
            if 'id' not in value:continue
            if method=='initialize':result={'protocolVersion':params.get('protocolVersion','2024-11-05'),'capabilities':{'tools':{}},'serverInfo':{'name':'todoboard','version':'0.1.0'}}
            elif method=='tools/list':result={'tools':TOOLS}
            elif method=='ping':result={}
            elif method=='tools/call':
                p=Pipeline(root)
                try:
                    name=params['name'];a=params.get('arguments',{})
                    if name in {'knowledge_read','knowledge_search'} and not p.config['knowledge']['enabled']:raise RuntimeError('knowledge disabled')
                    if name=='knowledge_read':data=p.ov.read(a['uri'])
                    elif name=='knowledge_search':data=p.ov.search(a['query'],p.config['knowledge']['searchRoot'],8)
                    elif name=='submit_todo':
                        ref=p.submit('mcp:'+str(__import__('uuid').uuid4()),'manual',a['title'],a['title']+'\n'+a.get('notes',''),actions=[])
                        data=p.board.add_candidate(a['title'],a.get('notes',''),refs=[SourceRef.from_dict(ref)]).to_dict()
                    elif name=='agent_event':apply_event(p,a['event']);data={'state':'recorded'}
                    else:raise ValueError('unknown tool')
                    result={'content':[{'type':'text','text':json.dumps(data,ensure_ascii=False)}]}
                finally:p.ledger.close()
            else:raise ValueError('unsupported method')
            response={'jsonrpc':'2.0','id':value['id'],'result':result}
        except Exception as e:response={'jsonrpc':'2.0','id':value.get('id') if 'value'in locals() else None,'error':{'code':-32603,'message':str(e)}}
        print(json.dumps(response,ensure_ascii=False),flush=True)

if __name__=='__main__':main()
