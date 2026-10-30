from contextlib import contextmanager
from pathlib import Path
import fcntl, json, os, tempfile
from .models import Board, Task, Execution, now_iso, stable_id

def atomic_json(path, value):
    atomic_text(path,json.dumps(value,ensure_ascii=False,indent=2)+'\n')

def atomic_text(path, value):
    path=Path(path); path.parent.mkdir(parents=True,exist_ok=True)
    fd,tmp=tempfile.mkstemp(prefix='.pending-',dir=path.parent)
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as out:
            out.write(value);out.flush();os.fsync(out.fileno())
        os.chmod(tmp,0o600);os.replace(tmp,path)
    finally: Path(tmp).unlink(missing_ok=True)

class BoardStore:
    """Re-read and mutate raw JSON under the same flock used by the Swift app."""
    def __init__(self, root):
        self.root=Path(root).expanduser().resolve();self.root.mkdir(parents=True,exist_ok=True)
        self.path=self.root/'tasks.json';self.backup=self.root/'tasks.json.bak'
    @contextmanager
    def lock(self):
        with (self.root/'tasks.lock').open('a+') as handle:
            fcntl.flock(handle,fcntl.LOCK_EX)
            try: yield
            finally: fcntl.flock(handle,fcntl.LOCK_UN)
    def raw(self):
        if not self.path.exists():return Board().to_dict()
        value=json.loads(self.path.read_text())
        if not isinstance(value,dict) or not isinstance(value.get('tasks'),list):raise ValueError('invalid board: original preserved')
        return value
    def read(self):return Board.from_dict(self.raw())
    def change(self,fn):
        with self.lock():
            value=self.raw();result=fn(value);value['updatedAt']=now_iso()
            atomic_json(self.path,value);atomic_json(self.backup,value);return result
    def bootstrap(self):
        with self.lock():
            if not self.path.exists():atomic_json(self.path,Board().to_dict())
    def add_candidate(self,title,notes='',tags=None,refs=None,*,source_key=None):
        if not isinstance(title,str) or not title.strip():raise ValueError('title is required')
        identity=source_key or stable_id('manual',title.strip(),notes.strip())
        def mutate(board):
            for t in board['tasks']:
                if t['id']==identity:return Task.from_dict(t)
            task=Task(identity,title.strip(),notes=notes,tags=tags or [],source_refs=refs or [],order=sum(t.get('status')=='backlog' for t in board['tasks']))
            board['tasks'].append(task.to_dict());return task
        return self.change(mutate)
    def update_execution(self,task_id,execution):
        def mutate(board):
            task=next((x for x in board['tasks'] if x['id']==task_id),None)
            if task is None:raise KeyError(task_id)
            task['execution']=execution.to_dict();return Task.from_dict(task)
        return self.change(mutate)
    def mark_done(self,task_id,evidence):
        if not evidence.strip():raise ValueError('acceptance evidence required')
        def mutate(board):
            task=next(x for x in board['tasks'] if x['id']==task_id)
            task.update(status='done',doneAt=now_iso())
            task.setdefault('execution',Execution(state='result').to_dict())['evidence'].append(evidence)
            return Task.from_dict(task)
        return self.change(mutate)
