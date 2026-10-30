"""Review only files intended for publication; never read the user's home data."""
import argparse,json,re,subprocess,sys,zipfile,tarfile,io
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
ALLOWED={'Sources','Tests','Resources','runtime','tests','scripts','config','examples','docs','integrations','schemas','.github','.archify','archify'}
ROOT_FILES={'Package.swift','pyproject.toml','package.json','package-lock.json','README.md','LICENSE','THIRD_PARTY_NOTICES.md','requirements-openviking.txt','.gitignore','SECURITY.md','CONTRIBUTING.md'}
PATTERNS=[re.compile(rb'/'+rb'Users/(?!runner(?:/|$))[^/\s"\']+/'),re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|sk-[A-Za-z0-9_-]{30,})'),re.compile(rb'(?i)(?:Bearer\s+)[A-Za-z0-9._-]{20,}'),re.compile(rb'(?:ou_|cli_)[a-f0-9]{16,}'),re.compile(rb'-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----')]
FORBIDDEN={'tasks.json','tasks.json.bak','ov.conf','ovcli.conf','agent-workspace.json','agent-deliveries.json','runtime-install.json','.env'}

def check(name,data):
    errors=[];path=Path(name)
    if path.name in FORBIDDEN or any(x in {'__pycache__','.venv','node_modules','.DS_Store'} for x in path.parts) or path.suffix in {'.sqlite','.log','.jsonl'}:errors.append('runtime/private file: '+name)
    if path.suffix.lower() not in {'.png','.zip','.gz'} and any(p.search(data) for p in PATTERNS):errors.append('sensitive marker: '+name)
    return errors

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--staged',action='store_true');parser.add_argument('--artifacts',action='store_true');a=parser.parse_args();errors=[]
    args=['git','ls-files','-z'] if not a.staged else ['git','diff','--cached','--name-only','-z']
    names=subprocess.check_output(args,cwd=ROOT).decode().split('\0')
    if not any(names):names=[str(p.relative_to(ROOT)) for p in ROOT.rglob('*') if p.is_file() and p.relative_to(ROOT).parts[0] in ALLOWED and not any(x in {'.vitepress','__pycache__'} for x in p.relative_to(ROOT).parts)]
    for name in filter(None,names):
        p=ROOT/name
        if not p.exists():continue
        if Path(name).parts[0] not in ALLOWED and name not in ROOT_FILES:errors.append('not in publication allowlist: '+name)
        errors+=check(name,p.read_bytes())
    # New history only: check blobs rather than relying on the current worktree.
    refs=subprocess.run(['git','rev-parse','--verify','HEAD'],cwd=ROOT,capture_output=True)
    if refs.returncode==0:
        objects=subprocess.check_output(['git','rev-list','--objects','--all'],cwd=ROOT).decode().splitlines()
        for line in objects:
            oid,_,name=line.partition(' ')
            if not name:continue
            if subprocess.check_output(['git','cat-file','-t',oid],cwd=ROOT).strip()==b'blob':errors+=check(name,subprocess.check_output(['git','cat-file','blob',oid],cwd=ROOT))
    if a.artifacts:
        for file in (ROOT/'dist').glob('*.zip'):
            with zipfile.ZipFile(file) as z:
                for item in z.infolist():
                    if not item.is_dir():errors+=check(item.filename,z.read(item))
        for file in (ROOT/'dist').glob('*.tar.gz'):
            with tarfile.open(file) as t:
                for item in t:
                    if item.isfile():errors+=check(item.name,t.extractfile(item).read())
    if errors:
        print('\n'.join(sorted(set(errors))),file=sys.stderr);return 1
    print(json.dumps({'state':'passed','files':len(list(filter(None,names))),'historyChecked':refs.returncode==0,'artifactsChecked':a.artifacts}));return 0

if __name__=='__main__':raise SystemExit(main())
