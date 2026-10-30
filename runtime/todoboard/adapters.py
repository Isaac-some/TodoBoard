import json, os, subprocess, uuid
from .rpc import RPC

class CodexAdapter:
    def __init__(self,root,ledger,settings):self.root,self.ledger,self.settings=root,ledger,settings
    def submit(self,packet,delivery_id):
        if self.settings.get('adapter')=='codex-cli':return self.cli(packet,delivery_id)
        return self.gui(packet,delivery_id)
    def cli(self,packet,delivery_id):
        # Never silently replay a possibly executed request after a crash.
        key='cli:'+delivery_id
        if self.ledger.get(key):raise RuntimeError('CLI outcome uncertain; inspect saved trace before explicit retry with a new request ID')
        self.ledger.put(key,{'started':True})
        folder=self.root/'deliveries'/delivery_id;folder.mkdir(parents=True,exist_ok=True)
        argv=[self.settings.get('executable','codex'),'exec','--json','-C',packet['cwd']]
        if self.settings.get('model'):argv+=['-m',self.settings['model']]
        argv+=['--skip-git-repo-check','-']
        with (folder/'events.jsonl').open('w') as out,(folder/'stderr.log').open('w') as err:
            r=subprocess.run(argv,input=packet['prompt'],text=True,stdout=out,stderr=err,env={**os.environ,'TODOBOARD_DATA_DIR':str(self.root),'TODOBOARD_DELIVERY_ID':delivery_id},timeout=self.settings.get('timeoutSeconds',3600))
        summary='';thread=None
        for line in (folder/'events.jsonl').read_text().splitlines():
            try:
                v=json.loads(line)
                if v.get('type')=='thread.started':thread=v.get('thread_id')
                item=v.get('item',{})
                if item.get('type')=='agent_message':summary=item.get('text','')
            except ValueError:continue
        return {'threadID':thread,'submissionID':delivery_id,'state':'result' if r.returncode==0 else 'failed','summary':summary,'evidence':[],'adapter':'codex-cli'}
    def gui(self,packet,delivery_id):
        executable=self.settings.get('executable','codex');key='gui:'+delivery_id
        saved=self.ledger.get(key,{})
        thread=saved.get('threadID')
        if not thread:
            with RPC(executable,packet['cwd']) as rpc:
                t=rpc.call('thread/start',{'cwd':packet['cwd'],'ephemeral':False,'approvalPolicy':'on-request','sandbox':'workspace-write','developerInstructions':packet.get('instructions','')})
                thread=t['thread']['id'];uuid.UUID(thread)
                self.ledger.put(key,{'threadID':thread})
                rpc.call('thread/name/set',{'threadId':thread,'name':packet.get('title','TodoBoard')})
        submission=None
        with RPC(executable,packet['cwd']) as rpc:
            cursor=None
            while True:
                params={'threadId':thread,'limit':100}
                if cursor:params['cursor']=cursor
                page=rpc.call('thread/queue/list',params)
                for item in page.get('data',[]):
                    if item.get('clientUserMessageId')==delivery_id:submission=item['id']
                cursor=page.get('nextCursor')
                if not cursor:break
            if not submission:
                history=rpc.call('thread/read',{'threadId':thread,'includeTurns':True})
                for turn in history.get('thread',{}).get('turns',[]):
                    for item in turn.get('items',[]):
                        if item.get('type')=='userMessage' and item.get('clientId')==delivery_id:submission=item['id']
            if not submission:
                r=rpc.call('thread/queue/add',{'threadId':thread,'clientUserMessageId':delivery_id,'input':[{'type':'text','text':packet['prompt']}]})
                q=r['queuedSubmission']
                if q.get('clientUserMessageId')!=delivery_id:raise RuntimeError('invalid queue receipt')
                submission=q['id']
        self.ledger.put(key,{'threadID':thread,'submissionID':submission})
        return {'threadID':thread,'submissionID':submission,'state':'queued','adapter':'codex-gui'}
