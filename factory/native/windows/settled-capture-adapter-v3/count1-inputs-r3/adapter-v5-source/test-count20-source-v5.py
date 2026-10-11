#!/usr/bin/env python3
"""Count20 repeat5 source admission; native archive stays held until root fills map."""
from __future__ import annotations
import copy, hashlib, importlib.util, json
from pathlib import Path
HERE=Path(__file__).resolve().parent; REPO=next(x for x in HERE.parents if (x/'factory').is_dir())
PENDING=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r4/count20-input-map-r4.pending.json'
META=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-metadata-r1/coordinator-repeat-r1/issued-metadata.json'
sp=importlib.util.spec_from_file_location('support',HERE/'support-v5.py'); support=importlib.util.module_from_spec(sp); assert sp.loader; sp.loader.exec_module(support)
pending=json.loads(PENDING.read_text(encoding='utf-8-sig')); metadata=json.loads(META.read_text(encoding='utf-8-sig'))
assert pending['count']==20 and pending['pending']['status']=='held-native-archive-absent'
assert len(pending['runs'])==20
root=REPO.resolve()
def ref(path):
 raw=(root/Path(*Path(path).parts)).read_bytes()
 return {'path':path,'bytes':len(raw),'sha256':'sha256:'+hashlib.sha256(raw).hexdigest()}
def read(r): return (root/Path(*Path(r['path']).parts)).read_bytes()
files=[ref(x) for x in pending['executionOverlay']['files']]
overlay={'kind':'factory-root-execution-overlay-v1','status':'executed-source-ref-only','overlayRoot':pending['executionOverlay']['overlayRoot'],'files':files}
support.validate_overlay(overlay,read,20)
support.validate_issued_ids(metadata,20,metadata['runRoot'])
# Real source faults: wrong repeat root, one script hash, noncanonical issued ID.
faults=[]
for name,mutate in [
 ('wrong-repeat-root',lambda x:(x.__setitem__('overlayRoot',support.COUNT_ROOTS[1]),x)[1]),
 ('wrong-repeat-hash',lambda x:(x['files'][0].__setitem__('sha256','sha256:'+'0'*64),x)[1]),
 ('wrong-count20-id',lambda x:support.validate_issued_ids(dict(metadata,captures=[dict(metadata['captures'][0],captureID='capture/'+'0'*31)]+metadata['captures'][1:]),20,metadata['runRoot'])),
]:
 try:
  if name=='wrong-count20-id': mutate(overlay)
  else: support.validate_overlay(mutate(copy.deepcopy(overlay)),read,20)
  raise AssertionError(name+' accepted')
 except (ValueError,AssertionError): faults.append(name)
assert faults==['wrong-repeat-root','wrong-repeat-hash','wrong-count20-id'],faults
print({'status':'pass','positive':'count20-repeat-r4-source-shape','futureSuccessor':'repeat-r5','runs':20,'nativeArchive':'held-absent','faults':faults,'nativeWindowActions':0})
