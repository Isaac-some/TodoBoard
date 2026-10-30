import json,multiprocessing,tempfile,unittest,uuid
from pathlib import Path
from todoboard.config import initialize,load
from todoboard.store import BoardStore,atomic_json
from todoboard.pipeline import Pipeline
from todoboard.models import Execution,SourceRef
from todoboard.delivery import dispatch,apply_event,context
from todoboard.hook import capture
from todoboard.sessions import capture_session,archive_submission,poll_commit_tasks

class FakeOV:
    def __init__(self):self.files={};self.offline=False;self.calls=[]
    def write(self,uri,content,**kw):
        if self.offline:raise OSError('offline')
        self.files[uri]=content
    def read(self,uri,**kw):
        if self.offline:raise OSError('offline')
        return self.files[uri]
    def search(self,*a):return [{'uri':u,'abstract':c[:30]} for u,c in self.files.items()]
    def request(self,method,path,payload=None,query=None):
        self.calls.append((method,path,payload))
        if '/archives/'in path:return {'messages':[{'role':'user','content':'Ship the synthetic demo.'}]}
        if path.endswith('/commit'):return {'session_id':path.split('/')[-2],'archived':True,'archive_uri':'viking://session/test/history/archive_001','task_id':'t1'}
        return {'uri':'viking://session/test','session_id':path.rsplit('/',1)[-1]}

def append(root,count):
    store=BoardStore(root)
    for x in range(count):store.add_candidate(str(uuid.uuid4()))

class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.root=initialize(self.tmp.name);self.ov=FakeOV();self.p=Pipeline(self.root,self.ov)
    def tearDown(self):self.p.ledger.close();self.tmp.cleanup()
    def enable(self):self.p.config['knowledge']['enabled']=True
    def test_empty_install_does_not_collect(self):
        c=load(self.root);self.assertEqual(c['sources']['directories'],[]);self.assertFalse(c['sources']['feishu']['enabled']);self.assertFalse(c['knowledge']['enabled']);self.assertEqual(c['sources']['codexWorkspaces'],[])
    def test_concurrent_writers_preserve_foreign_fields(self):
        self.p.board.bootstrap();value=self.p.board.raw();value['extension']={'keep':True};atomic_json(self.root/'tasks.json',value)
        jobs=[multiprocessing.Process(target=append,args=(str(self.root),12)) for _ in range(4)]
        for j in jobs:j.start()
        for j in jobs:j.join();self.assertEqual(j.exitcode,0)
        self.assertEqual(len(self.p.board.read().tasks),48);self.assertEqual(self.p.board.raw()['extension'],{'keep':True})
    def test_archival_gate_offline_retry_dedup_and_discard(self):
        self.enable();self.ov.offline=True
        ref=self.p.submit('source-A','local','Synthetic','Ship the synthetic demo.',actions=[{'title':'Ship demo','evidence':'Ship the synthetic demo.','locator':'line 1'}])
        self.p.run();self.assertEqual(self.p.board.read().tasks,[]);self.assertTrue((self.root/'materials'/ref['id']/'original.md').exists())
        self.ov.offline=False
        with self.p.ledger.db:self.p.ledger.db.execute('UPDATE jobs SET retry_at=0')
        self.p.run();task=self.p.board.read().tasks[0];self.assertEqual(task.status,'backlog');self.assertEqual(task.source_refs[0].locator,'line 1')
        self.p.board.change(lambda b:b['tasks'][0].update(status='trash'))
        self.p.submit('source-A','local','Synthetic','Ship the synthetic demo.\nA revised paragraph.',actions=[{'title':'Ship demo','evidence':'Ship the synthetic demo.'}]);self.p.run()
        self.assertEqual(len(self.p.board.read().tasks),1);self.assertEqual(self.p.board.read().tasks[0].status,'trash')
    def test_no_candidate_without_real_evidence(self):
        self.enable();self.p.submit('s','local','T','A statement.',actions=[{'title':'Invented','evidence':'not present'}]);self.p.run();self.assertEqual(self.p.board.read().tasks,[])
        self.assertEqual(self.p.ledger.pending(),[])
    def test_result_event_never_completes_card_and_acceptance_is_retained(self):
        self.enable();t=self.p.board.add_candidate('Synthetic task')
        event={'event_id':'event-1','task_id':t.id,'state':'result','summary':'Verified synthetic output','evidence':['commit:synthetic']}
        apply_event(self.p,event);apply_event(self.p,event)
        self.assertEqual(self.p.board.read().tasks[0].status,'backlog');self.assertEqual(self.p.ledger.db.execute('SELECT count(*) FROM events').fetchone()[0],1)
        self.p.run();self.assertFalse(any('/accepted/'in x for x in self.ov.files))
        self.p.board.mark_done(t.id,'Human acceptance of synthetic output');self.p.run();self.assertTrue(any('/accepted/'in x for x in self.ov.files))
    def test_context_uses_retained_source_when_ov_offline(self):
        ref=self.p.submit('r','local','Source','Exact source evidence.',actions=[]);t=self.p.board.add_candidate('T',refs=[SourceRef.from_dict(ref)])
        self.ov.offline=True;r=context(self.p,[t.id]);self.assertIn('Exact source evidence.',r['sources'][0]['content'])
    def test_cli_submission_is_durable_and_retry_keeps_receipt(self):
        self.p.config['defaultAgent']={'adapter':'codex-cli','executable':'not-called-in-submit'}
        t=self.p.board.add_candidate('T');self.p.board.change(lambda b:b['tasks'][0].update(status='today'));packet={'version':1,'requestID':str(uuid.uuid4()),'cwd':str(self.root),'taskIDs':[t.id],'prompt':'Synthetic'}
        first=dispatch(self.p,packet);second=dispatch(self.p,packet);self.assertEqual(first,second)
        self.assertEqual(self.p.ledger.db.execute("SELECT count(*) FROM jobs WHERE kind='agent-cli'").fetchone()[0],1)
        self.assertEqual(self.p.board.read().tasks[0].execution.state,'queued');self.assertEqual(self.p.board.read().tasks[0].status,'today')
    def test_capture_is_explicitly_scoped_and_ignores_tools(self):
        transcript=self.root/'transcript.jsonl';transcript.write_text('\n'.join(json.dumps(x) for x in [
          {'type':'response_item','payload':{'type':'message','role':'user','content':[{'type':'input_text','text':'Record a synthetic observation.'}]}},
          {'type':'response_item','payload':{'type':'function_call','arguments':'excluded tool data'}},
          {'type':'response_item','payload':{'type':'message','role':'assistant','content':[{'type':'output_text','text':'Synthetic reply.'}]}}]))
        value={'cwd':str(self.root),'session_id':'test-session','transcript_path':str(transcript),'last_assistant_message':'Synthetic reply.'}
        capture(value,self.root);self.assertEqual(list((self.root/'inbox').glob('*.json')),[])
        c=load(self.root);c['sources']['codexWorkspaces']=[str(self.root)];atomic_json(self.root/'config.json',c)
        capture(value,self.root);capture(value,self.root);files=list((self.root/'inbox').glob('*.json'));self.assertEqual(len(files),1)
        event=json.loads(files[0].read_text());self.assertEqual(len(event['messages']),2)
        self.enable();capture_session(self.p,event);capture_session(self.p,event)
        self.assertEqual(len([x for x in self.ov.calls if x[1].endswith('/messages/batch')]),1)
        receipt=json.loads(next((self.root/'inbox').glob('commit-*.json')).read_text());archive_submission(self.p,receipt)
        self.assertTrue(list((self.root/'materials').glob('*/original.md')))
    def test_invalid_card_file_is_preserved(self):
        path=self.root/'tasks.json';path.write_text('broken')
        with self.assertRaises(ValueError):self.p.board.add_candidate('T')
        self.assertEqual(path.read_text(),'broken')
    def test_compacted_transcript_retains_new_turns_without_repeating_old_ones(self):
        self.enable()
        first={'id':'first','sessionID':'session','messages':[{'role':'user','content':'old','created_at':'1'},{'role':'assistant','content':'reply','created_at':'2'}]}
        capture_session(self.p,first)
        compacted={'id':'compacted','sessionID':'session','messages':[first['messages'][-1],{'role':'user','content':'new','created_at':'3'}]}
        capture_session(self.p,compacted);capture_session(self.p,compacted)
        batches=[x[2]['messages'] for x in self.ov.calls if x[1].endswith('/messages/batch')]
        self.assertEqual(len(batches),2);self.assertEqual(batches[1],[compacted['messages'][-1]])
    def test_phase_two_failure_is_visible_separately_from_archive_receipt(self):
        self.enable();self.ov.capabilities={'sessions'}
        self.p.ledger.put('memory-task:failed',{'taskID':'failed','state':'pending'})
        self.ov.request=lambda *a,**k:{'status':'failed','stage':'failed','error':'model authorization expired'}
        poll_commit_tasks(self.p)
        self.assertEqual(self.p.ledger.get('memory-task:failed')['state'],'failed')
        self.assertEqual(self.p.board.read().tasks,[])
    def test_repeated_source_keeps_original_record_time(self):
        first=self.p.submit('stable','local','T','same text',observed_at='2026-01-01T00:00:00Z')
        second=self.p.submit('stable','local','T','same text',observed_at='2026-02-01T00:00:00Z')
        self.assertEqual(first,second)

if __name__=='__main__':unittest.main()
