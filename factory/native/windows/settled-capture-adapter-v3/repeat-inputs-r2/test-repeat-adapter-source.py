#!/usr/bin/env python3
"""Call adapter-v4 overlay validator against Count20 source capsule + faults."""
import copy, hashlib, importlib.util, json
from pathlib import Path

HERE=Path(__file__).resolve().parent
REPO=HERE.parents[4]
ADAPTER=REPO/'factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v4.py'
ISSUED=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-repeat-v1/observed-metadata-r1/coordinator-repeat-r1/issued-metadata.json'
OVERLAY=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r2'
ISSUER=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/issuer-overlay-r1/issue-before-launch-prefixed-r1.ps1'

def ref(path):
 raw=path.read_bytes()
 return {'path':str(path.relative_to(REPO)).replace('\\','/'),'sha256':'sha256:'+hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
def main():
 spec=importlib.util.spec_from_file_location('adapter_v4_repeat_source',ADAPTER); mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
 issued=json.loads(ISSUED.read_text()); issued['captures']=[dict(c,provenance=dict(c.get('provenance') or {},producer=mod.ISSUER_PRODUCER)) for c in issued['captures']]
 issued_raw=json.dumps(issued).encode()
 issued_ref={'path':'tmp/swiftright-repeat-issued-source-capsule.json','sha256':'sha256:'+hashlib.sha256(issued_raw).hexdigest(),'bytes':len(issued_raw)}
 source_ref=ref(REPO/'factory/oracle/mac/padding-origin-fresh-v1/actual/capture-index.json')
 tuple_doc={'sourceInputs':{'captureIndex':source_ref}}
 tuple_raw=json.dumps(tuple_doc).encode()
 tuple_ref={'path':'tmp/swiftright-repeat-tuple-source-capsule.json','sha256':'sha256:'+hashlib.sha256(tuple_raw).hexdigest(),'bytes':len(tuple_raw)}
 # Capsule uses actual repeat metadata shape plus actual overlay/issuer bytes; no native or reader action.
 files=[ref(OVERLAY/n) for n in ('resume-issued-coordinator-repeat-r2.ps1','interactive-task-repeat-r2.ps1','dispatch-repeat-r2.ps1','capture-repeat-r2.ps1','integration-prefixed-ids-r1.ps1')]
 capsule={'roles':{'issuedMetadata':issued_ref,'tuple':tuple_ref},'tupleSource':{'captureIndex':source_ref},'executionOverlay':{'kind':'factory-root-execution-overlay-v1','status':'executed-source-ref-only','overlayRoot':'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r2','baseProducerProfile':{'profile':'measured'} ,'files':files},'issuerSource':dict(ref(ISSUER),name=mod.ISSUER_SOURCE_NAME)}
 capsule['roles']['producerProfile']=capsule['executionOverlay']['baseProducerProfile']
 read=lambda r: issued_raw if r['path']=='tmp/swiftright-repeat-issued-source-capsule.json' else (tuple_raw if r['path']=='tmp/swiftright-repeat-tuple-source-capsule.json' else (REPO/r['path']).read_bytes())
 mod._overlay_v4(capsule,read)
 for label,mutate in (
  ('wrong-overlay-hash',lambda c:c['executionOverlay']['files'][0].update(sha256='sha256:'+'0'*64)),
  ('wrong-overlay-root',lambda c:c['executionOverlay'].update(overlayRoot='factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r4')),
  ('wrong-issuer-hash',lambda c:c['issuerSource'].update(sha256='sha256:'+'0'*64)),
 ):
  bad=copy.deepcopy(capsule); mutate(bad)
  try: mod._overlay_v4(bad,read)
  except ValueError: continue
  raise AssertionError(label)
 print('PASS Count20 adapter source capsule baseline + 3 real overlay/issuer faults; native/lock/compiler/remote actions=0')
if __name__=='__main__': main()
