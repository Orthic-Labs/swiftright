#!/usr/bin/env python3
"""Source-only closure audit for repeat-r6 first-proof preflight.

Checks imported PowerShell function definitions & required order. It never
executes PowerShell, native code, GUI code, locks, or remote actions.
"""
from __future__ import annotations
import json, re
from pathlib import Path

REPO=Path(__file__).resolve().parents[7]
PACKET=REPO/'factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/windows-exit-proof-r2/repeat-r6-dependency-audit-v1'
MAP=json.loads((PACKET/'dependency-closure-r6.json').read_text())

def source(rel):
    p=REPO/rel
    assert p.is_file(), f'missing source: {rel}'
    return p.read_text(encoding='utf-8')

order=MAP['firstProofImportOrder']
sources={rel:source(rel) for rel in order}
definitions={}
for rel,text in sources.items():
    for name in re.findall(r'(?m)^function\s+([A-Za-z0-9_-]+)',text):
        definitions.setdefault(name,[]).append(rel)
missing=[]
for rel,names in MAP['firstProofSymbols'].items():
    candidates=[x for x in sources if x.endswith(rel)]
    assert candidates, f'missing imported source mapping: {rel}'
    for name in names:
        if name not in definitions: missing.append(name)
assert not missing, f'missing callable definitions: {missing}'
schema_index=order.index('factory/native/windows/padding-capture-lease-capture-v3/dependencies/uia-worker/schema.ps1')
cleanup_index=order.index('factory/native/windows/padding-capture-lease-capture-v3/support/cleanup.ps1')
stream_index=order.index('factory/native/windows/padding-capture-lease-capture-v3/support/stream-seal.ps1')
assert schema_index > cleanup_index and schema_index > stream_index
first=source('factory/native/windows/padding-capture-lease-capture-v3/support/first-proof-repeat-r6.ps1')
assert 'Assert-UiaSnapshotWorkerProof' not in first, 'first-proof must not directly execute worker validator'
dispatch=source('factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6/dispatch-repeat-r6.ps1')
resume=source('factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6/resume-issued-coordinator-repeat-r6.ps1')
assert 'first-proof-repeat-r6.ps1' in dispatch and 'first-proof-repeat-r6.ps1' in resume
without_schema={rel:text for rel,text in sources.items() if not rel.endswith('/uia-worker/schema.ps1')}
without_schema_defs={name for text in without_schema.values() for name in re.findall(r'(?m)^function\s+([A-Za-z0-9_-]+)',text)}
assert 'Assert-UiaSnapshotWorkerProof' not in without_schema_defs
faults={'schema-import-omission':'rejected'}
print(json.dumps({'status':'pass','firstProofImports':len(order),'symbols':sum(map(len,MAP['firstProofSymbols'].values())),'missing':[],'faults':faults,'nativeWindowActions':0,'lockActions':0},sort_keys=True))
