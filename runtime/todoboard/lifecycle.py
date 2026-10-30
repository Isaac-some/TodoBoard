"""Per-data-directory LaunchAgent; never replaces another installation."""
import hashlib,plistlib,subprocess,sys,os
from pathlib import Path
from .store import atomic_json
from .models import now_iso

def identity(root):return 'io.github.isaac-some.todoboard.worker.'+hashlib.sha256(str(root).encode()).hexdigest()[:10]
def manage(root,action):
    label=identity(root);plist=Path.home()/'Library/LaunchAgents'/f'{label}.plist';domain='gui/'+str(os.getuid())
    if action=='start':
        plist.parent.mkdir(parents=True,exist_ok=True);logs=root/'logs';logs.mkdir(exist_ok=True)
        value={'Label':label,'ProgramArguments':[sys.executable,'-m','todoboard.worker','--data-dir',str(root)],'RunAtLoad':True,'KeepAlive':True,'WorkingDirectory':str(root),'EnvironmentVariables':{'PATH':os.environ.get('PATH','/usr/bin:/bin'),'PYTHONPATH':str(Path(__file__).resolve().parents[1])},'StandardOutPath':str(logs/'worker.log'),'StandardErrorPath':str(logs/'worker-error.log')}
        plist.write_bytes(plistlib.dumps(value))
        atomic_json(root/'worker-status.json',{'state':'starting'})
        subprocess.run(['launchctl','bootout',domain+'/'+label],capture_output=True)
        r=subprocess.run(['launchctl','bootstrap',domain,str(plist)],capture_output=True,text=True)
        if r.returncode:raise RuntimeError('LaunchAgent registration failed')
    elif action=='stop':
        subprocess.run(['launchctl','bootout',domain+'/'+label],capture_output=True)
        plist.unlink(missing_ok=True)
        atomic_json(root/'worker-status.json',{'state':'stopped','stoppedAt':now_iso()})
    return {'state':action,'label':label}
