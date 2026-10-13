from pathlib import Path
import json,hashlib,importlib.util,tempfile,sys,copy
from unittest.mock import patch
from factory.gate.mac_origin_admission import mac_origin_admission_issues
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/pipeline/paired-padding-origin-fresh-v2-operational-v1';O=P/'independent-review-v1';V1=R/'factory/pipeline/paired-padding-origin-fresh-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text())
def module(p,name):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
for packet in [P,V1]:
 for row in load(packet/'stage-manifest.json')['files']:
  f=packet/row['path'];assert sha(f)==row['sha256'].removeprefix('sha256:') and f.stat().st_size==row['bytes']
m=module(P/'report.py','fresh_operational_review');v1=module(V1/'report.py','fresh_v1_review')
before={str(p):sha(p) for p in m.EVIDENCE.rglob('*') if p.is_file()};controls={};original=m.execute_workflow

def checked(origin,artifact,out):
 pins=v1.source_pins(artifact);case,cfg,accept=v1.case_inputs(artifact);rows,refs=v1.captures(artifact,pins,case)
 assert len(rows)==20
 origin_results=[mac_origin_admission_issues(row,lambda ref:origin(capture=row,reference=ref)) for row in rows];assert all(not x for x in origin_results),origin_results[:1]
 controls['semanticOriginBaseline20']=True
 class Changed:
  def __call__(self,**kw):
   raw=origin(**kw)
   if kw['reference']['path'].endswith('CaptureHost.swift'):return bytes([raw[0]^1])+raw[1:]
   return raw
 bad=mac_origin_admission_issues(rows[0],lambda ref:Changed()(capture=rows[0],reference=ref));assert bad and any('hash' in s.lower() for s in bad);controls['sameLengthSourceFault']=bad
 class Missing:
  def __call__(self,**kw):
   if kw['reference']['path'].endswith('CaptureHost.swift'):raise ValueError('review missing mapping')
   return origin(**kw)
 bad=mac_origin_admission_issues(rows[0],lambda ref:Missing()(capture=rows[0],reference=ref));assert bad;controls['missingMappingFault']=bad
 from factory.pipeline import workflow
 class RawFault:
  def __call__(self,**kw):
   raw=artifact(**kw)
   if kw['reference']['path'].endswith('/run-001/capture.json'):
    data=json.loads(raw);data['id']+='-fault';return json.dumps(data).encode()
   return raw
 rejected=workflow.collect([case],[m.EVIDENCE],reader=RawFault());assert len(rejected['captures'])==19 and 'differing from expected hash' in rejected['diagnostics'][0]['reason'];controls['validJSONArtifactFault']=rejected['diagnostics'][0]['reason']
 return original(origin,artifact,out)
with tempfile.TemporaryDirectory(prefix='fresh-operational-independent-') as d:
 out=Path(d)/'actual'; calls=[]
 with patch.object(m,'execute_workflow',side_effect=checked),patch.object(m,'verify_source_pins',side_effect=lambda:calls.append(True)),patch.object(sys,'argv',['report.py','--output',str(out)]):assert m.main()==0
 report=load(out/'report.json');receipt=load(out/'rehydration-process-receipt.json');assert not Path(receipt['tempRoot']).exists()
 assert report['macOS']['originProof']['verified']==180 and report['windows']['typedCaptureCount']==0 and not report['qualification']['parityQualified']
 assert report['candidateOnly'] is True and report['frozen'] is False
 assert receipt['nativeExecutions']==receipt['compilerExecutions']==0
 assert not calls,'source verify unexpectedly called'
 controls['sourcePinFunctionCalled']=False
 controls['actualTempRemoved']=True
 assert load(out/'workflow-gate-evidence/captures.json')==load(P/'workflow-gate-evidence/captures.json')
 result={'verdict':'CLEAR_ACTUAL_ARCHIVE_REPLAY_HOLD_MISSING_FROZEN_SOURCE_PIN_GATE','sourceSha256':sha(P/'report.py'),'stageSha256':sha(P/'stage-manifest.json'),'controls':controls,'actualCounts':{'schemaCollected':20,'semanticOriginAccepted':20,'descriptorsVerified':180,'windowsTyped':0,'parityQualified':False},'rehydrationReceipt':receipt,'findings':[{'id':'dead-source-pin-gate','proof':'verify_source_pins defined but actual main never invokes it (independent spy observed zero calls). execute_workflow uses workflow current-file-hash snapshots, unlike v1 explicit immutable runs/source gate. Recorded actual bytes independently match frozen packet, but reusable v2 cannot claim immutable source closure.','required':'Call & retain immutable source pin verification before workflow consumption; test changed valid capture/source pin fails specific gate. Preserve this frozen packet in successor.'}], 'scope':'Actual archive-only Python rehydration & production collect/comparator/F9/F10 offline replay; no installed/current tool execution, compiler/native/remote actions. Full semantic origin guard baseline+source/mapping faults tested; no Windows parity claim.'}
 (O/'report.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
 v1result={'verdict':'CLEAR_FRESH_V1_PINNED_CAPTURE_ORIGIN_INPUTS','sourceSha256':sha(V1/'report.py'),'stageSha256':sha(V1/'stage-manifest.json'),'actualOriginGuardAccepted':20,'actualDescriptorCount':180,'windowsTyped':0,'parityQualified':False,'verified':'Actual v1 source_pins/case_inputs/captures replay using operational archive-only origin reader. All frozen source/capture/AX/clock pins pass; semantic origin guards accept20; no raw mutation. Historical v1 toolcache mapping remains cache-dependent; operational successor supplies data-only rehydration.'}
 (V1/'independent-review-v1/report.json').write_text(json.dumps(v1result,indent=2,sort_keys=True)+'\n')
assert before=={str(p):sha(p) for p in m.EVIDENCE.rglob('*') if p.is_file()}
print(json.dumps({'v2report':sha(O/'report.json'),'v1report':sha(V1/'independent-review-v1/report.json'),'sourcePinCalled':False,'tempRemoved':True}))
