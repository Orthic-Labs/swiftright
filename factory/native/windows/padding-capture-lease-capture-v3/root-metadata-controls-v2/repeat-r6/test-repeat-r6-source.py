#!/usr/bin/env python3
"""Source-only Count20 repeat-r6 successor controls.

No PowerShell, lock, GUI, compiler, or native action is performed here.
"""
from __future__ import annotations
import hashlib, importlib.util, json
from pathlib import Path

REPO=Path(__file__).resolve().parents[6]
OVERLAY=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6'
SUPPORT=REPO/'factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v5-source/support-v5.py'
PROFILE=REPO/'factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v5-source/source-profile-v5.json'
FIRST=REPO/'factory/native/windows/padding-capture-lease-capture-v3/support/first-proof-repeat-r6.ps1'

spec=importlib.util.spec_from_file_location('support_v5',SUPPORT); support=importlib.util.module_from_spec(spec); spec.loader.exec_module(support)
profile=json.loads(PROFILE.read_text())
rows=profile['repeatR6']
assert len(rows)==5

def ref(row):
 p=REPO/row['path']; b=p.read_bytes(); assert len(b)==row['bytes']; assert 'sha256:'+hashlib.sha256(b).hexdigest()==row['sha256']; return {'path':row['path'],'sha256':row['sha256'],'bytes':len(b)}
files=[ref(row) for row in rows]
overlay={'kind':'factory-root-execution-overlay-v1','status':'executed-source-ref-only','overlayRoot':'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6','files':files}
def read(r):
 p=REPO/r['path']; b=p.read_bytes(); assert 'sha256:'+hashlib.sha256(b).hexdigest()==r['sha256']; return b
support.validate_overlay(overlay,read,20)

# Wrong overlay root, copied-metadata hash, & coordinator metadata namespace each reject
faults={}
for name, mutate in {
 'wrong-overlay-root':lambda x:x.update(overlayRoot=x['overlayRoot'].replace('repeat-r6','repeat-r5')),
 'wrong-overlay-hash':lambda x:x['files'][0].update(sha256='sha256:'+'0'*64),
}.items():
 bad=json.loads(json.dumps(overlay)); mutate(bad)
 try: support.validate_overlay(bad,read,20)
 except Exception: faults[name]='rejected'
 else: faults[name]='accepted-BUG'

src=FIRST.read_text()
required=[
 r"coordinator-single-r1\issued-metadata.json",
 '$copiedIssuedHash=',
 'if($copiedIssuedHash -cne $issuedHash)',
 "$controlIssuedHashProperty=$control.PSObject.Properties['issuedMetadataHash']",
 'First coordinator issued metadata hash join failed',
 'Assert-LeaseIssuedMetadata $originalIssuedPath $issuedHash',
]
assert all(x in src for x in required), 'first-proof coordinator/copy hash guard missing'
for marker in required:
 bad=src.replace(marker,'',1)
 if all(x in bad for x in required): faults['missing-'+marker[:18]]='accepted-BUG'
 else: faults['missing-'+marker[:18]]='rejected'
assert all(v=='rejected' for v in faults.values())
print(json.dumps({'status':'pass','positive':'repeat-r6-overlay+coordinator-copy-hash','files':len(rows),'faults':faults,'nativeWindowActions':0},sort_keys=True))
