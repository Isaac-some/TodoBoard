"""HTTP-only integration; uses OV's native content, search and session APIs."""
import json, os, urllib.parse, urllib.request
from dataclasses import dataclass
from pathlib import Path

@dataclass
class OpenVikingConfig:
    url: str='http://127.0.0.1:1933'
    api_key: str|None=None
    account: str|None=None
    user: str|None=None
    peer_id: str|None=None
    @classmethod
    def load(cls,settings=None):
        settings=settings or {};path=Path(settings.get('configFile','~/.config/todoboard/ovcli.conf')).expanduser()
        v=json.loads(path.read_text()) if path.exists() else {}
        if os.getenv('OPENVIKING_CREDENTIAL_SOURCE')=='env' or not v:
            v.update(url=os.getenv('OPENVIKING_URL',os.getenv('OPENVIKING_BASE_URL',v.get('url',cls.url))),api_key=os.getenv('OPENVIKING_API_KEY',v.get('api_key')),account=os.getenv('OPENVIKING_ACCOUNT',v.get('account')),user=os.getenv('OPENVIKING_USER',v.get('user')),actor_peer_id=os.getenv('OPENVIKING_PEER_ID',v.get('actor_peer_id')))
        return cls(v.get('url',cls.url),v.get('api_key'),v.get('account'),v.get('user'),v.get('actor_peer_id'))

class OpenVikingClient:
    capabilities={'read','write','search','sessions'}
    def __init__(self,config=None,timeout=120):self.config,self.timeout,self.checked=config or OpenVikingConfig.load(),timeout,False
    def request(self,method,path,payload=None,query=None):
        if path!='/health' and not self.checked:
            health=self.health()
            if health.get('version')!='0.5.2.1':raise RuntimeError('OpenViking version mismatch: expected official 0.5.2.1')
            self.checked=True
        url=self.config.url.rstrip('/')+path
        if query:url+='?'+urllib.parse.urlencode(query)
        headers={'Content-Type':'application/json'}
        if self.config.api_key:headers['Authorization']='Bearer '+self.config.api_key
        for k,v in [('X-OpenViking-Account',self.config.account),('X-OpenViking-User',self.config.user),('X-OpenViking-Actor-Peer',self.config.peer_id)]:
            if v:headers[k]=v
        req=urllib.request.Request(url,method=method,headers=headers,data=json.dumps(payload).encode() if payload is not None else None)
        try:
            with urllib.request.urlopen(req,timeout=self.timeout) as r:value=json.load(r)
        except urllib.error.HTTPError as e:raise RuntimeError(f'OpenViking HTTP {e.code}: {path}') from None
        if value.get('status')=='error':raise RuntimeError('OpenViking operation failed: '+path)
        return value.get('result',value)
    def health(self):
        result=self.request('GET','/health')
        if result.get('version')!='0.5.2.1':raise RuntimeError('OpenViking version mismatch: expected official 0.5.2.1')
        return result
    def read(self,uri,offset=0,limit=-1):return self.request('GET','/api/v1/content/read',query={'uri':uri,'offset':offset,'limit':limit})
    def write(self,uri,content,mode='replace',wait=True):return self.request('POST','/api/v1/content/write',{'uri':uri,'content':content,'mode':mode,'wait':wait})
    def search(self,query,target_uri='viking://resources',limit=8):return self.request('POST','/api/v1/search/find',{'query':query,'target_uri':target_uri,'limit':limit})
