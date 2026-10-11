from pathlib import Path
import hashlib,json,unittest
from factory.gate.test_windows_exit_admission import Fixture
R=Path(__file__).resolve().parents[4];F=R/'factory/pipeline/exit-admission-audit-v1/guard-evidence-v1';O=Path(__file__).parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((F/'root-stage-manifest.json').read_text())
for x in m['files']:
 b=(R/x['path']).read_bytes();assert len(b)==x['bytes'] and 'sha256:'+hashlib.sha256(b).hexdigest()==x['hash']
assert sha(R/'factory/gate/windows_exit_admission.py')=='3f149daa68b0f2c8fe45180efd1aaf0b6934657cc0a4056e7f72a4346e14f19d'
f=Fixture();assert f.result()['status']=='pass';controls=[]
for name,changes in [('wrong-compile-invocation',{'argv':'unrelated.exe --no-source','cwd':'D:\\foreign'}),('nonterminal-cleanup-status',{'status':'hold-cleanup'})]:
 f=Fixture()
 if name.startswith('wrong'):f.objects['compile'].update(changes)
 else:f.objects['outcome']['cleanup'].update(changes)
 f.rebind();result=f.result();assert result['status']=='pass';controls.append({'fault':name,'accepted':True,'mutatedFields':changes,'issues':result['issues']})
actual=R/'factory/native/windows/round1-seeded-native-v5/single-stack-overlay-r1/replays/run-001/native-01/capture-outcome.json';j=json.loads(actual.read_text(encoding='utf-8-sig'));assert j['primaryError']=='Owned renderer child deadline' and j['cleanup']['kernelWaitResult']==0
f=Fixture();f.objects['outcome']['primaryError']=j['primaryError'];f.rebind();result=f.result();assert result['status']=='blocked' and result['issues']==['primary or stream failure forbids qualified capture']
schema=json.loads((R/'factory/spec/schema/capture.schema.json').read_text());assert 'additionalProperties' in schema['properties']['meta']['properties']['conditions']
report={'kind':'independent-windows-exit-admission-guard-v1','decision':'blocked-for-exact-compiler-invocation-and-terminal-certificate-admission','producerPins':m['files'],'sourceStageSha256':sha(F/'root-stage-manifest.json'),'suppliedTestsPassed':11,'independentSemanticFaults':controls,'actualFailedStack':{'path':str(actual.relative_to(R)),'sha256':sha(actual),'primaryError':j['primaryError'],'kernelWaitResult':0,'primaryFailureAdmission':'blocked despite successful cleanup; isolated actual error transplanted into otherwise accepted raw fixture'},'schema':'conditions.windowsExitProof object permitted by canonicalValue; captured hash computed over capture & independent raw hashes, no circular capture binding','positiveScope':'synthetic archive only; nativeParityGranted remains false','requiredChanges':['Derive &bind expected compiler invocation source/cwd/tool/target/build flags from archived plan/request authority, with isolated wrong argv/cwd faults','Require retained cleanup permitted terminal status (matching production certificate), isolated status fault'],'reviewActions':'read-only plus offline Python test/fault replay; no native/remote/Git'}
p=O/'guard-review-v1.json';p.write_text(json.dumps(report,indent=2)+'\n');print(sha(p))
