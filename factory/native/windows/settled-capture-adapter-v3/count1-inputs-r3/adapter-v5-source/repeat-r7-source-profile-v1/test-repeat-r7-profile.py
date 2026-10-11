#!/usr/bin/env python3
"""Source-only profile & pending native input-map controls for repeat-r7."""
from __future__ import annotations
import copy,hashlib,json,re
from pathlib import Path
HERE=Path(__file__).resolve().parent; REPO=next(p for p in HERE.parents if (p/'factory').is_dir())
P=json.loads((HERE/'source-profile-repeat-r7.json').read_text())
def digest(p): return 'sha256:'+hashlib.sha256((REPO/p).read_bytes()).hexdigest()
def require_profile(x):
 assert x['kind']=='factory-repeat-r7-source-profile-v1' and x['expectedCount']==20
 assert x['status']=='source-bound-pending-native-r7'
 assert x['inputMapContract']['status']=='pending-native-r7'
 assert x['inputMapContract']['expectedRows']==20
 assert x['inputMapContract']['requiredActualHashes'] is True
 assert set(x['inputMapContract']['requiredJoins'])=={'issuedMetadataHash','coordinatorHash','captureOutcomeHash','rawStreamsHash','workerExitProofHash','sourceBundleHash'}
 assert x['inputMapContract']['syntheticFallback'] is False and x['inputMapContract']['posthocRelabel'] is False
 assert len(x['overlaySources'])==5 and len(x['inputMapContract']['requiredRoles'])==13
 for ref in x['overlaySources']+[x['firstProofHelper'],x['schemaDependency']]:
  p=REPO/ref['path']; assert p.is_file(); assert ref['sha256']==digest(ref['path']); assert ref['bytes']==p.stat().st_size
 assert x['schemaDependency']['sha256']=='sha256:ca1590fa7d41669ff4217ad282c1a1d1af747ffcb0b14ee002bcad0c3eafbb61'
 assert x['abiInvariant']=={'captureDllImportCount':5,'requiredImports':['user32.dll'],'forbiddenImports':['user42.dll'],'sameAsR6CaptureSource':'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r6/capture-repeat-r6.ps1'}
require_profile(P)
faults={}
for label,mut in [('wrong-count',lambda x:x['inputMapContract'].update(expectedRows=1)),('synthetic-fallback',lambda x:x['inputMapContract'].update(syntheticFallback=True)),('missing-hash-join',lambda x:x['inputMapContract']['requiredJoins'].pop()),('wrong-schema-hash',lambda x:x['schemaDependency'].update(sha256='sha256:'+'0'*64))]:
 q=copy.deepcopy(P); mut(q)
 try: require_profile(q)
 except (AssertionError,StopIteration): faults[label]='rejected'
 else: faults[label]='accepted-BUG'
assert all(v=='rejected' for v in faults.values())
print(json.dumps({'status':'pass','positive':'r7-profile+pending-input-map-contract','faults':faults,'nativeWindowActions':0,'lockActions':0},sort_keys=True))
