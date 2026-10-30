import json, sqlite3, time

class Ledger:
    def __init__(self,root):
        self.db=sqlite3.connect(str(root/'runtime.sqlite'),timeout=30)
        self.db.row_factory=sqlite3.Row
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.executescript('''CREATE TABLE IF NOT EXISTS jobs(id TEXT PRIMARY KEY,kind TEXT NOT NULL,payload TEXT NOT NULL,state TEXT NOT NULL DEFAULT 'pending',attempts INTEGER DEFAULT 0,error TEXT,retry_at REAL DEFAULT 0);
CREATE TABLE IF NOT EXISTS kv(id TEXT PRIMARY KEY,value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY,payload TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS deliveries(id TEXT PRIMARY KEY,packet TEXT NOT NULL,state TEXT NOT NULL,receipt TEXT);''')
    def get(self,key,default=None):
        row=self.db.execute('SELECT value FROM kv WHERE id=?',(key,)).fetchone();return json.loads(row[0]) if row else default
    def put(self,key,value):
        with self.db:self.db.execute('INSERT OR REPLACE INTO kv VALUES(?,?)',(key,json.dumps(value,ensure_ascii=False)))
    def enqueue(self,key,kind,payload):
        with self.db:self.db.execute('INSERT OR IGNORE INTO jobs(id,kind,payload) VALUES(?,?,?)',(key,kind,json.dumps(payload,ensure_ascii=False)))
    def pending(self):return self.db.execute("SELECT * FROM jobs WHERE state IN ('pending','retry') AND retry_at<=? ORDER BY rowid",(time.time(),)).fetchall()
    def state(self,key,state,error=None):
        with self.db:self.db.execute('UPDATE jobs SET state=?,error=?,attempts=attempts+1,retry_at=? WHERE id=?',(state,error,time.time()+60 if state=='retry' else 0,key))
    def close(self):self.db.close()
