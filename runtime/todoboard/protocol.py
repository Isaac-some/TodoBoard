"""Validation of the version 1 process boundary; JSON Schemas live in schemas/."""
import uuid

def task_packet(value):
    if value.get('version')!=1:raise ValueError('unsupported task packet version')
    uuid.UUID(value['requestID'])
    for key in ['cwd','prompt']:
        if not isinstance(value.get(key),str) or not value[key].strip():raise ValueError(key+' is required')
    if not isinstance(value.get('taskIDs'),list) or not all(isinstance(x,str) for x in value['taskIDs']):raise ValueError('taskIDs must be strings')
    return value
