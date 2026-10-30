"""Local durable worker. No GUI, inbox messaging, or private global scans."""
import argparse, fcntl, json, time
from datetime import datetime,timedelta,timezone
from pathlib import Path
from .config import data_root,initialize
from .pipeline import Pipeline
from .feishu import FeishuClient
from .meeting_sources import collect
from .models import stable_id
from .store import atomic_json

def tick(root):
    p=Pipeline(root)
    try:
        for row in p.ledger.db.execute("SELECT id FROM jobs WHERE state='running'").fetchall():p.ledger.state(row['id'],'retry','worker restarted')
        for value in p.config['sources']['directories']:
            path=Path(value).expanduser().resolve()
            if not path.is_dir():continue
            for file in path.rglob('*'):
                if not file.is_file() or file.suffix.lower() not in {'.md','.txt','.srt','.json'} or file.is_symlink():continue
                if not file.resolve().is_relative_to(path):continue
                if file.stat().st_size>10_000_000:continue
                try:p.submit(str(file),'local',file.name,file.read_text(encoding='utf-8'),source_uri=file.as_uri())
                except (OSError,UnicodeError,ValueError) as e:p.ledger.put('source-error:'+stable_id('file',str(file)),{'state':'retained','error':type(e).__name__})
        options=p.config['sources']['feishu'];now=datetime.now(timezone.utc)
        if options.get('enabled') and time.time()-p.ledger.get('feishu:lastAttempt',0)>=options.get('intervalMinutes',20)*60:
            p.ledger.put('feishu:lastAttempt',time.time())
            start=datetime.fromisoformat(p.ledger.get('feishu:coveredUntil',(now-timedelta(days=options.get('initialLookbackDays',7))).isoformat()))
            # Overlap catches delayed artifacts; unfinished windows are never clipped.
            result=collect(root,root/'collection',FeishuClient(root,{'feishu':options}),start-timedelta(days=1),now,domains=('meetings','minutes'))
            atomic_json(root/'collection/status.json',result)
            if result['coverage'] and all(c['state']=='success' for c in result['coverage']):p.ledger.put('feishu:coveredUntil',now.isoformat())
        for event_file in sorted((root/'inbox').glob('*.json')):
            try:
                v=json.loads(event_file.read_text());kind=v['kind']
                if kind=='ov-commit':
                    from .sessions import archive_submission
                    archive_submission(p,v)
                elif kind=='codex-capture':
                    from .sessions import capture_session
                    from .delivery import apply_hook_result
                    apply_hook_result(p,v)
                    capture_session(p,v)
                elif kind=='agent-result':
                    from .delivery import apply_hook_result
                    apply_hook_result(p,v)
                else:raise ValueError('unknown inbox event')
                event_file.rename(event_file.with_suffix('.processed'))
            except Exception as e:atomic_json(event_file.with_suffix('.error'),{'error':type(e).__name__})
        p.run()
        from .delivery import poll_gui_results
        poll_gui_results(p)
    finally:p.ledger.close()

def main(argv=None):
    parser=argparse.ArgumentParser();parser.add_argument('--data-dir');parser.add_argument('--once',action='store_true');a=parser.parse_args(argv)
    root=initialize(a.data_dir)
    with (root/'worker.lock').open('a+') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return False
        while True:
            try:tick(root);atomic_json(root/'worker-status.json',{'lastTick':datetime.now(timezone.utc).isoformat(),'state':'running'})
            except Exception as e:atomic_json(root/'worker-status.json',{'state':'error','error':str(e)})
            if a.once:return True
            from .config import load
            time.sleep(max(5,int(load(root).get('pollSeconds',60))))

if __name__=="__main__":main()
