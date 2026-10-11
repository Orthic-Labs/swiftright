#!/usr/bin/env python3
"""Source-only composed successor controls on preserved r7 input map."""
from __future__ import annotations
import copy, importlib.util, json
from pathlib import Path
HERE=Path(__file__).resolve().parent; REPO=next(x for x in HERE.parents if (x/'factory').is_dir())
INPUT=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native-r7/adapter-inputs-r7.actual.json'
sp=importlib.util.spec_from_file_location('support',HERE/'support-v5.py'); support=importlib.util.module_from_spec(sp); assert sp.loader; sp.loader.exec_module(support)
ap=importlib.util.spec_from_file_location('adapter',HERE/'adapter-v5.py'); adapter=importlib.util.module_from_spec(ap); assert ap.loader; ap.loader.exec_module(adapter)
DOC=json.loads(INPUT.read_text(encoding='utf-8-sig')); ROOT=REPO.resolve()
def read(ref):
 raw=(ROOT/Path(*Path(ref['path']).parts)).read_bytes();
 if 'sha256:'+__import__('hashlib').sha256(raw).hexdigest()!=ref['sha256'] or (ref.get('bytes') not in (None,0) and len(raw)!=ref['bytes']): raise ValueError('byte/hash')
 return raw
adapter._overlay_v4(DOC,read)
issued=json.loads(read(DOC['roles']['issuedMetadata']).decode('utf-8-sig')); support.validate_node_epochs(issued)
faults=[]
for name,mutate in [
 ('wrong-overlay-root',lambda d:(d['executionOverlay'].__setitem__('overlayRoot',support.COUNT_ROOTS[1]),d)[1]),
 ('wrong-overlay-hash',lambda d:(d['executionOverlay']['files'][0].__setitem__('sha256','sha256:'+'0'*64),d)[1]),
 ('wrong-canonical-id',lambda d:issued.__setitem__('captures',[dict(issued['captures'][0],captureID='capture/'+'0'*31)])),
 ('wrong-node-epochs',lambda d:support.validate_node_epochs(dict(issued,nodeEpochs=[2,1]))),
]:
 try:
  if name in ('wrong-node-epochs','wrong-canonical-id'): mutate(DOC)
  else: adapter._overlay_v4(mutate(copy.deepcopy(DOC)),read)
  raise AssertionError(name+' accepted')
 except (ValueError,AssertionError): faults.append(name)
assert faults==['wrong-overlay-root','wrong-overlay-hash','wrong-canonical-id','wrong-node-epochs'],faults
print({'status':'pass','positive':'r7-source-admitted-overlay','faults':faults,'nativeWindowActions':0})
