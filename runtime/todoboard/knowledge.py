"""Version 1 knowledge adapter; custom stores declare their actual capabilities."""
import json, subprocess
from .ov import OpenVikingClient, OpenVikingConfig

class CommandKnowledge:
    def __init__(self,settings):self.settings=settings;self.capabilities=set(settings.get('capabilities',[]));self.timeout=120
    def invoke(self,operation,**payload):
        if operation not in self.capabilities:raise RuntimeError('knowledge capability unavailable: '+operation)
        r=subprocess.run(self.settings['command'],input=json.dumps({'version':1,'operation':operation,**payload}),text=True,capture_output=True,timeout=self.timeout)
        if r.returncode:raise RuntimeError('knowledge adapter failed; input retained')
        result=json.loads(r.stdout)
        if result.get('version')!=1:raise ValueError('unsupported knowledge response')
        return result['result']
    def health(self):return {'provider':'command','capabilities':sorted(self.capabilities)}
    def read(self,uri,**options):return self.invoke('read',uri=uri,**options)
    def write(self,uri,content,**options):return self.invoke('write',uri=uri,content=content,**options)
    def search(self,query,target_uri,limit):return self.invoke('search',query=query,target_uri=target_uri,limit=limit)

def create(settings):
    provider=settings.get('provider','openviking')
    if provider=='openviking':return OpenVikingClient(OpenVikingConfig.load(settings))
    if provider=='command':return CommandKnowledge(settings)
    raise ValueError('unknown knowledge provider')
