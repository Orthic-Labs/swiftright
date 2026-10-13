#!/usr/bin/env python3
"""Source-bound controls for telemetry-only execute-r7/repeat-r4 successors."""
from __future__ import annotations
import copy, hashlib, importlib.util, json
from pathlib import Path

HERE=Path(__file__).resolve().parent; REPO=HERE.parents[4]
ADAPTER=HERE/'adapter-v4.py'
ISSUER=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/issuer-overlay-r1/issue-before-launch-prefixed-r1.ps1'
SOURCE=REPO/'factory/oracle/mac/padding-origin-fresh-v1/actual/capture-index.json'
R7=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r7'
R6=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r6'
R4=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r4'
R3=REPO/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r3'
R7_HASHES={
 'coordinator-r7.ps1':'1d959f332c31d4843ed1217f5994c05f0e1df3a5801385c9fbbed9c08be39fd8',
 'interactive-task-r7.ps1':'25f18fab1c286c9f4f121e59ce0955b3c3a7d02b7bea5ce3d56b25dcdb4893b4',
 'dispatch-r7.ps1':'33acdf62c846895a4c0360068917b89d657ace5f4ba68d503a454ea77ed493d0',
 'capture-repeat-r7.ps1':'049c9d39d80a9c30017190cb57ab6e55093b3e65926e18a019e5b6aa3090b2e3',
 'integration-prefixed-ids-r1.ps1':'d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'}
R4_HASHES={
 'resume-issued-coordinator-repeat-r4.ps1':'b2889bac231d337f15c88ad7bb800ba44a2b0330de8be66163fbd2f4b648153b',
 'interactive-task-repeat-r4.ps1':'02d33efee1cb14f59e6182c63dc5490e06cd380b3f0dd25165b2f76e2ebd79f0',
 'dispatch-repeat-r4.ps1':'c96c0c8acdf6fd2bc042fd704544c318cecd2dc622eb938474f5eac971fbb695',
 'capture-repeat-r4.ps1':'52da5743464fc22b2ce5a81bb5099d138ab40a13602798d46f3f2a52bb5a81c5',
 'integration-prefixed-ids-r1.ps1':'d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'}

def ref(path:Path):
 raw=path.read_bytes(); return {'path':str(path.relative_to(REPO)).replace('\\','/'),'sha256':'sha256:'+hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
def capsule(mod,root,hashes,count,suffix):
 issued_raw=json.dumps({'expectedCount':count}).encode(); issued={'path':'control/issued.json','sha256':'sha256:'+hashlib.sha256(issued_raw).hexdigest(),'bytes':len(issued_raw)}
 src=ref(SOURCE); tuple_raw=json.dumps({'sourceInputs':{'captureIndex':src}}).encode(); tuple_ref={'path':'control/tuple.json','sha256':'sha256:'+hashlib.sha256(tuple_raw).hexdigest(),'bytes':len(tuple_raw)}
 files=[ref(root/name) for name in hashes]
 profile={'profile':'frozen-v4'}
 cap={'roles':{'issuedMetadata':issued,'tuple':tuple_ref,'producerProfile':profile},'tupleSource':{'captureIndex':src},'executionOverlay':{'kind':'factory-root-execution-overlay-v1','status':'executed-source-ref-only','overlayRoot':suffix,'baseProducerProfile':profile,'files':files},'issuerSource':dict(ref(ISSUER),name=mod.ISSUER_SOURCE_NAME)}
 def read(x):
  if x['path']=='control/issued.json': return issued_raw
  if x['path']=='control/tuple.json': return tuple_raw
  return (REPO/x['path']).read_bytes()
 return cap,read

def main():
 spec=importlib.util.spec_from_file_location('adapter_v4',ADAPTER); mod=importlib.util.module_from_spec(spec); assert spec.loader; spec.loader.exec_module(mod)
 assert {k:v[7:] for k,v in mod.EXECUTION_OVERLAY_R7_HASHES.items()}==R7_HASHES
 assert {k:v[7:] for k,v in mod.EXECUTION_OVERLAY_REPEAT_R4_HASHES.items()}==R4_HASHES
 csp=importlib.util.spec_from_file_location('count1_producer',HERE/'produce-count1-inputs-r3.py'); cm=importlib.util.module_from_spec(csp); assert csp.loader; csp.loader.exec_module(cm)
 rsp=importlib.util.spec_from_file_location('repeat_producer',HERE.parent/'repeat-inputs-r2/produce-repeat-inputs-r2.py'); rm=importlib.util.module_from_spec(rsp); assert rsp.loader; rsp.loader.exec_module(rm)
 assert {k:v[7:] for k,v in cm.EXECUTION_OVERLAY_R7_HASHES.items()}==R7_HASHES
 assert {k:v[7:] for k,v in rm.EXECUTION_OVERLAY_REPEAT_R4_HASHES.items()}==R4_HASHES
 # Telemetry-only delta: remove new fields & successor names/deadline, yielding exact parents.
 old= (R6/'capture-repeat-r6.ps1').read_text(); new=(R7/'capture-repeat-r7.ps1').read_text()
 strip="ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt};hwnd=$hwnd.ToInt64();"
 assert new.replace('-r7','-r6').replace(strip,'')==old
 old=(R3/'capture-repeat-r3.ps1').read_text(); new=(R4/'capture-repeat-r4.ps1').read_text()
 assert new.replace('-r4','-r3').replace(strip,'').replace('AddSeconds(30)','AddSeconds(6)')==old
 for root,hashes,count,suffix in ((R7,R7_HASHES,1,'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r7'),(R4,R4_HASHES,20,'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r4')):
  cap,read=capsule(mod,root,hashes,count,suffix); mod._overlay_v4(cap,read)
  bad=copy.deepcopy(cap); bad['executionOverlay']['overlayRoot']=suffix.replace('r7','r6').replace('r4','r3')
  try: mod._overlay_v4(bad,read); raise AssertionError('wrong root accepted')
  except ValueError: pass
  bad=copy.deepcopy(cap); bad['executionOverlay']['files'][0]['sha256']='sha256:'+'0'*64
  try: mod._overlay_v4(bad,read); raise AssertionError('wrong hash accepted')
  except ValueError: pass
 # Old proof capsule remains an explicit rejection fixture, never relabeled.
 result=json.loads((HERE/'windows-exit-proof-r1/source-control-r1/source-control-result-r1.json').read_text())
 assert result['controlOnly'] and result['status']=='blocked' and result['nativeWindowActions']==0
 assert any(x['predicate']=='observation/ownedIdentity missing' for x in result['legacyMismatches'])
 print('PASS telemetry r7/r4 exact five-file contracts; telemetry-only deltas; root/hash rejects; legacy proof reject; effects=0')
if __name__=='__main__': main()
