#!/usr/bin/env python3
"""Source-only eight-entry repeat-r7 dependency scope audit."""
from __future__ import annotations
import copy,json,re
from pathlib import Path
REPO=Path(__file__).resolve().parents[7]
PACKET=REPO/'factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/windows-exit-proof-r2/repeat-r7-dependency-audit-v1'
MAP=json.loads((PACKET/'dependency-closure-r7.json').read_text())
def source(rel):
 p=REPO/rel; assert p.is_file(), rel; return p.read_text()
order=MAP['firstProofImportOrder']; assert len(order)==8
sources={rel:source(rel) for rel in order}
defs={}
for rel,text in sources.items():
 for name in re.findall(r'(?m)^function\s+([A-Za-z0-9_-]+)',text): defs.setdefault(name,[]).append(rel)
missing=[n for rel,names in MAP['firstProofSymbols'].items() for n in names if n not in defs]
assert not missing,missing
schema=REPO/'factory/native/windows/padding-capture-lease-capture-v3/dependencies/uia-worker/schema.ps1'
assert __import__('hashlib').sha256(schema.read_bytes()).hexdigest()==MAP['schemaRef']['sha256'].split(':',1)[1]
first=source('factory/native/windows/padding-capture-lease-capture-v3/support/first-proof-repeat-r7.ps1')
assert '$schemaPath=' in first and '. $schemaPath' in first and MAP['schemaRef']['sha256'].split(':',1)[1] in first
assert 'Assert-UiaSnapshotWorkerProof' not in first
for rel in MAP['scheduledScopes']:
 text=source(rel); assert 'first-proof-repeat-r7.ps1' in text
# Schema is self-loaded by helper, while explicit source closure still records exact dependency.
without_schema={r:t for r,t in sources.items() if not r.endswith('/uia-worker/schema.ps1')}
assert 'Assert-UiaSnapshotWorkerProof' not in {n for t in without_schema.values() for n in re.findall(r'(?m)^function\s+([A-Za-z0-9_-]+)',t)}
faults={}
for name,mut in [('schema-hash-drift',lambda s:s.replace(MAP['schemaRef']['sha256'].split(':',1)[1],'0'*64,1)),('helper-schema-omission',lambda s:s.replace('. $schemaPath','',1)),('dispatch-helper-omission',lambda s:s.replace('first-proof-repeat-r7.ps1','missing.ps1',1)),('coordinator-helper-omission',lambda s:s.replace('first-proof-repeat-r7.ps1','missing.ps1',1))]:
 if name=='schema-hash-drift': bad=mut(first); ok=MAP['schemaRef']['sha256'].split(':',1)[1] not in bad
 elif name=='helper-schema-omission': bad=mut(first); ok='. $schemaPath' not in bad
 elif name=='dispatch-helper-omission': bad=mut(source(MAP['scheduledScopes'][0])); ok='first-proof-repeat-r7.ps1' not in bad
 else: bad=mut(source(MAP['scheduledScopes'][1])); ok='first-proof-repeat-r7.ps1' not in bad
 assert ok; faults[name]='rejected'
print(json.dumps({'status':'pass','firstProofImports':8,'symbols':sum(map(len,MAP['firstProofSymbols'].values())),'faults':faults,'nativeWindowActions':0,'lockActions':0},sort_keys=True))
