"""Bounded local JSON-RPC client. GUI handoff never runs a turn in a temporary server."""
import json, subprocess, selectors, time

class RPC:
    def __init__(self,executable='codex',cwd=None):self.executable,self.cwd,self.seq=executable,cwd,0
    def __enter__(self):
        self.process=subprocess.Popen([self.executable,'app-server'],cwd=self.cwd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,text=False)
        self.buffer=b'';self.selector=selectors.DefaultSelector();self.selector.register(self.process.stdout,selectors.EVENT_READ)
        self.call('initialize',{'clientInfo':{'name':'todoboard','version':'0.1.0'},'capabilities':{'experimentalApi':True}})
        self.send({'method':'initialized'});return self
    def send(self,obj):self.process.stdin.write((json.dumps(obj,ensure_ascii=False)+'\n').encode());self.process.stdin.flush()
    def call(self,method,params):
        self.seq+=1;seq=self.seq;self.send({'id':seq,'method':method,'params':params});deadline=time.monotonic()+90
        while time.monotonic()<deadline:
            while b'\n' in self.buffer:
                line,self.buffer=self.buffer.split(b'\n',1);msg=json.loads(line)
                if msg.get('id')!=seq:continue
                if 'error' in msg:raise RuntimeError('Codex RPC '+method+': '+str(msg['error'].get('message','unsupported')))
                return msg['result']
            if self.selector.select(max(0,deadline-time.monotonic())):
                import os
                chunk=os.read(self.process.stdout.fileno(),65536)
                if not chunk:raise RuntimeError('Codex app-server closed')
                self.buffer+=chunk
        raise TimeoutError('Codex RPC timed out: '+method)
    def __exit__(self,*args):
        self.selector.close();self.process.stdin.close()
        try:self.process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            self.process.terminate()
            try:self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:self.process.kill();self.process.wait()
