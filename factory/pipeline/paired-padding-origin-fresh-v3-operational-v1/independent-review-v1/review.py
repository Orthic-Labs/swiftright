from pathlib import Path
import json,hashlib,importlib.util,tempfile,sys
from unittest.mock import patch
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/pipeline/paired-padding-origin-fresh-v3-operational-v1';O=P/'independent-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text())
s=load(P/'stage-manifest.json')
for x in s['files']:
 p=P/x['path'];assert sha(p)==x['sha256'].removeprefix('sha256:') and p.stat().st_size==x['size']
spec=importlib.util.spec_from_file_location('fresh_operational_v3_review',P/'report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
guard=m.frozen_source_guard();assert guard['count']==69
original=Path.read_bytes;target=m.LIVE_CONFIG.parent/'run-001/capture.json'
def altered(p):
 raw=original(p)
 if p==target:
  v=json.loads(raw);v['id']+='-valid-json-fault';return json.dumps(v).encode()
 return raw
with patch.object(Path,'read_bytes',altered):
 try:m.frozen_source_guard()
 except ValueError as e:reason=str(e);assert reason=='frozen run changed: 001/capture.json'
 else:raise AssertionError('frozen run drift accepted')
base=m.load_v2_module();raw_before={str(p):sha(p) for p in base.EVIDENCE.rglob('*') if p.is_file()}
with tempfile.TemporaryDirectory(prefix='fresh-v3-independent-') as d:
 out=Path(d)/'actual'
 with patch.object(sys,'argv',['report.py','--output',str(out)]):assert m.main()==0
 result=load(out/'report.json');receipt=load(out/'rehydration-process-receipt.json')
 assert result['frozenInputGuard']['count']==69 and result['macOS']['originProof']['verified']==180
 assert result['windows']['typedCaptureCount']==0 and result['candidateOnly'] is True and result['frozen'] is False and not result['qualification']['parityQualified']
 assert not Path(receipt['tempRoot']).exists() and receipt['nativeExecutions']==receipt['compilerExecutions']==0
 gate=load(out/'workflow-gate-evidence/gate-results.json');issues=[i for x in gate['gateResults'] for i in x['report']['issues']];assert not any('mac-origin:' in i for i in issues)
 assert load(out/'workflow-gate-evidence/captures.json')==load(P/'run-33877/workflow-gate-evidence/captures.json')
 for name in ['rehydration-helper.stdout.txt','rehydration-helper.stderr.txt','rehydration-process-receipt.json']:(O/name).write_bytes((out/name).read_bytes())
 report={'verdict':'CLEAR_ACTUAL_FROZEN_MAC20_ARCHIVE_REPLAY','sourceSha256':sha(P/'report.py'),'stageSha256':sha(P/'stage-manifest.json'),'actualCounts':{'frozenBlobs':69,'MacSchemaCollected':20,'originGuardAccepted':20,'originDescriptors':180,'windowsTyped':0,'parityQualified':False},'independentValidJSONRunFault':reason,'actualControls':result['controls'],'tempRemoved':True,'execution':'Offline Python source guard & archive-only tool rehydration, production collect/comparator/F9/F10; no native/compiler/remote execution','findings':[{'id':'producer-run-control-reason','scope':'coverage','proof':'Producer frozen-run-fault modifies pin manifest, rejected by manifest hash; independent actual run-byte fault here reaches exact frozen run changed: 001/capture.json.'},{'id':'runtime-dependency-scope','scope':'preflight boundary','proof':'Main executes v2 module from path without own embedded source pin; parses rehydration plan before plan hash check. Reviewed current dependency bytes & root frozen source preflight supply current execution closure; standalone main does not pin every imported module before exec/parse.'}],'qualification':'Mac20 origin accepted; Windows0; candidateOnly true/frozen false; raw timing & parity held'}
 (O/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
assert raw_before=={str(p):sha(p) for p in base.EVIDENCE.rglob('*') if p.is_file()}
print(sha(O/'report.json'))
