#!/usr/bin/env python3
"""Exercise adapter-v4 r5/r3 overlay contracts with real source bytes only."""
from pathlib import Path
import copy,hashlib,importlib.util,json
HERE=Path(__file__).resolve().parent; REPO=HERE.parents[4]
OVERLAY=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r5'
OVERLAY_R6=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r6'
ISSUER=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/issuer-overlay-r1/issue-before-launch-prefixed-r1.ps1'
SOURCE=REPO/'factory/oracle/mac/padding-origin-fresh-v1/actual/capture-index.json'
EXPECTED={
'coordinator-r5.ps1':'3e32c96c858f1233836ecb6a9191050dde39387fabe70c8cc1d8222e6cb83761',
'interactive-task-r5.ps1':'6c9b9720ec840f62e4922dc3590709cf31e619fa9de2a29fa3b58a6f67c82f44',
'dispatch-r5.ps1':'a5b147e031e156c6f31392d7167e21a2dfb45c7bd9b18099cfa7d54b7ffdd0dc',
'capture-repeat-r5.ps1':'6580498b8e12636af46a9f180dfb606bc2f4e81ccd320c6c18969fc0abde8255',
'integration-prefixed-ids-r1.ps1':'d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'}
EXPECTED_R6={'coordinator-r6.ps1':'7dc5df6b6425474643b1540ecbb10483e705be3846ca2b12e66330abb44281f4','interactive-task-r6.ps1':'9e4c825373e41def23a6d5c376e90097bde95612bfa887cba836f73e96f2f528','dispatch-r6.ps1':'df39a14812a80a3131485808766c5b617f5b61d365d0a5302b9363b1319a1340','capture-repeat-r6.ps1':'12adb458565e0c6398625cae54e992230e17fa3c2aafb05353109e2d55fc1e8a','integration-prefixed-ids-r1.ps1':'d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'}
def ref(path):
 raw=path.read_bytes();return {'path':str(path.relative_to(REPO)).replace('\\','/'),'sha256':'sha256:'+hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
def main():
 spec=importlib.util.spec_from_file_location('adapter_v4_contracts',HERE/'adapter-v4.py');mod=importlib.util.module_from_spec(spec);assert spec.loader;spec.loader.exec_module(mod)
 assert {k:v[7:] for k,v in mod.EXECUTION_OVERLAY_R5_HASHES.items()}==EXPECTED
 assert set(mod.EXECUTION_OVERLAY_R5_HASHES)==set(EXPECTED)
 assert {k:v[7:] for k,v in mod.EXECUTION_OVERLAY_R6_HASHES.items()}==EXPECTED_R6
 assert set(mod.EXECUTION_OVERLAY_R6_HASHES)==set(EXPECTED_R6)
 issued_raw=json.dumps({'expectedCount':1}).encode();issued={'path':'tmp/issued.json','sha256':'sha256:'+hashlib.sha256(issued_raw).hexdigest(),'bytes':len(issued_raw)}
 tuple_raw=json.dumps({'sourceInputs':{'captureIndex':ref(SOURCE)}}).encode();tuple_ref={'path':'tmp/tuple.json','sha256':'sha256:'+hashlib.sha256(tuple_raw).hexdigest(),'bytes':len(tuple_raw)}
 files=[ref(OVERLAY/name) for name in EXPECTED]
 cap={'roles':{'issuedMetadata':issued,'tuple':tuple_ref,'producerProfile':{}},'tupleSource':{'captureIndex':ref(SOURCE)},'executionOverlay':{'kind':'factory-root-execution-overlay-v1','status':'executed-source-ref-only','overlayRoot':'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r5','baseProducerProfile':{},'files':files},'issuerSource':dict(ref(ISSUER),name=mod.ISSUER_SOURCE_NAME)}
 read=lambda x: issued_raw if x['path']=='tmp/issued.json' else tuple_raw if x['path']=='tmp/tuple.json' else (REPO/x['path']).read_bytes()
 mod._overlay_v4(cap,read)
 for label,mutate in [('wrong-library-contract',lambda c:c['executionOverlay']['files'][3].update(sha256='sha256:'+'0'*64)),('wrong-overlay-root',lambda c:c['executionOverlay'].update(overlayRoot='factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r4'))]:
  bad=copy.deepcopy(cap);mutate(bad)
  try: mod._overlay_v4(bad,read)
  except ValueError: continue
  raise AssertionError(label)
 assert all(ref(OVERLAY_R6/name)['sha256'][7:]==digest for name,digest in EXPECTED_R6.items())
 print('PASS adapter-v4 execute-r5 + execute-r6 five-hash contracts; r5 rejection faults=2; effects=0')
if __name__=='__main__': main()
