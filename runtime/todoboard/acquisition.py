"""Compatibility seam for the existing, read-only meeting collector."""
import json
from pathlib import Path
from .store import atomic_json
from .pipeline import Pipeline
save=atomic_json

def enqueue(path,runtime):
    metadata=json.loads(Path(path).read_text());root=Path(runtime).parent
    while root.parent!=root and not (root/'config.json').is_file():root=root.parent
    if not (root/'config.json').is_file():raise ValueError('runtime config not found')
    p=Pipeline(root)
    try:
        ref=p.submit(metadata.get('sourceMeetingID',metadata.get('minuteToken','')), 'feishu-meeting',metadata['title'],Path(metadata['transcriptPath']).read_text(),metadata['startAt'],metadata.get('sourceURL'))
        return {'jobID':ref['id'],'state':'pending'}
    finally:p.ledger.close()
