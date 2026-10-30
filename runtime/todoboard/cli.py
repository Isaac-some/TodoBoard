"""Public local API. An empty installation scans no existing personal data."""
import argparse, json, shutil, sys, uuid
from pathlib import Path
from .config import initialize, load
from .pipeline import Pipeline
from .models import SourceRef, now_iso, stable_id
from .delivery import dispatch, apply_event, context
from .store import atomic_json

def main(argv=None):
    p=argparse.ArgumentParser(prog='todoboardctl');p.add_argument('--data-dir')
    s=p.add_subparsers(dest='command',required=True)
    for name in ['init','status','doctor','start','stop','run-once']:s.add_parser(name)
    a=s.add_parser('submit-todo');a.add_argument('title');a.add_argument('--notes',default='');a.add_argument('--source-uri');a.add_argument('--source-id')
    a=s.add_parser('source');a.add_argument('file');a.add_argument('--id');a.add_argument('--kind',default='local');a.add_argument('--title');a.add_argument('--observed-at');a.add_argument('--actions-file')
    a=s.add_parser('source-json');a.add_argument('file')
    a=s.add_parser('dispatch');a.add_argument('task_id');a.add_argument('--agent-id',default='');a.add_argument('--cwd',required=True);a.add_argument('--instruction',default='');a.add_argument('--request-id')
    a=s.add_parser('handoff');a.add_argument('--packet-file',required=True)
    a=s.add_parser('event');a.add_argument('file')
    a=s.add_parser('context');a.add_argument('task_id')
    args=p.parse_args(argv);root=initialize(args.data_dir)
    try:
        if args.command in {'start','stop'}:
            from .lifecycle import manage
            result=manage(root,args.command)
        elif args.command=='run-once':
            from .worker import main as run_worker
            checked=run_worker(['--data-dir',str(root),'--once']);result={'state':'checked' if checked else 'worker-already-running'}
        else:
            pipeline=Pipeline(root)
            try:
                if args.command=='init':
                    pipeline.board.bootstrap();result={'version':1,'dataDir':str(root),'state':'initialized','collectionEnabled':False}
                elif args.command=='status':
                    result={'dataDir':str(root),'jobs':[dict(r) for r in pipeline.ledger.db.execute('SELECT id,kind,state,attempts,error FROM jobs')],'memoryTasks':[json.loads(r[0]) for r in pipeline.ledger.db.execute("SELECT value FROM kv WHERE id LIKE 'memory-task:%'")],'inboxErrors':len(list((root/'inbox').glob('*.error'))),'tasks':len(pipeline.board.read().tasks),'worker':json.loads((root/'worker-status.json').read_text()) if (root/'worker-status.json').exists() else None}
                elif args.command=='doctor':
                    config=load(root);result={'python':sys.version.split()[0],'dataDir':str(root),'codex':bool(shutil.which(config['defaultAgent'].get('executable','codex'))),'knowledgeEnabled':config['knowledge']['enabled'],'openvikingRequired':'0.5.2.1'}
                    if config['knowledge']['enabled']:result['knowledge']=pipeline.ov.health()
                elif args.command=='submit-todo':
                    ref=pipeline.submit(args.source_id or str(uuid.uuid4()),'manual',args.title,args.title+'\n'+args.notes,source_uri=args.source_uri,actions=[])
                    task=pipeline.board.add_candidate(args.title,args.notes,refs=[SourceRef.from_dict(ref)],source_key=stable_id('manual',args.source_id) if args.source_id else None)
                    result=task.to_dict()
                elif args.command in {'source','source-json'}:
                    if args.command=='source-json':
                        value=json.loads(Path(args.file).read_text());
                        if value.get('version',1)!=1:raise ValueError('unsupported source version')
                        result=pipeline.submit(**{k:v for k,v in value.items() if k!='version'})
                    else:
                        file=Path(args.file).expanduser().resolve();actions=json.loads(Path(args.actions_file).read_text()) if args.actions_file else None
                        result=pipeline.submit(args.id or file.as_uri(),args.kind,args.title or file.name,file.read_text(encoding='utf-8'),args.observed_at,file.as_uri(),actions)
                elif args.command=='context':result=context(pipeline,[args.task_id])
                elif args.command in {'dispatch','handoff'}:
                    if args.command=='handoff':packet=json.loads(Path(args.packet_file).read_text())
                    else:
                        task=next(t for t in pipeline.board.read().tasks if t.id==args.task_id)
                        packet={'version':1,'requestID':args.request_id or str(uuid.uuid4()),'taskIDs':[task.id],'agentID':args.agent_id,'title':task.title,'cwd':str(Path(args.cwd).expanduser().resolve()),'prompt':task.title+'\n'+task.notes+'\n'+args.instruction}
                    result=dispatch(pipeline,packet)
                elif args.command=='event':apply_event(pipeline,json.loads(Path(args.file).read_text()));result={'state':'recorded'}
            finally:pipeline.ledger.close()
        print(json.dumps(result,ensure_ascii=False))
    except Exception as e:
        print(json.dumps({'error':type(e).__name__,'message':str(e)},ensure_ascii=False),file=sys.stderr);return 1
    return 0

if __name__=='__main__':raise SystemExit(main())
