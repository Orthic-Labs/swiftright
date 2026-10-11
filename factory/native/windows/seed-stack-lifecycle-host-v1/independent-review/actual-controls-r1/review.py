from pathlib import Path
import hashlib,json,base64
R=Path(__file__).resolve().parents[6];F=R/'factory/native/windows/seed-stack-lifecycle-host-v1';O=Path(__file__).parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
M=F/'root-stage-manifest.json';assert sha(M)=='fada5ea5455bce12333823d51760563eaf5855c26613bc90710fb4e1edb27d10';m=read(M);assert len(m['files'])==35
for x in m['files']:
 p=R/x['path'];assert sha(p)==x['sha256'].removeprefix('sha256:') and p.stat().st_size==x['bytes']
entry=F/'root-before-compile-controls.ps1';assert sha(entry)=='824e698483125e67ca4e1e420c490c0c901b96c4860ca039cf242beb1867adc1'
fetch=read(F/'root-lifecycle-controls-complete-r1.json');assert fetch['scpExit']==0 and len(fetch['files'])==13
for p,h in fetch['files'].items():assert sha(R/p)==h
process=read(F/'root-lifecycle-controls-r1-process.json');start=read(F/'root-lifecycle-controls-r1-start.json');assert process['exitCode']==0 and process['startedAt']==start['startedAt'];assert sha(entry)==start['scriptSha256'];assert sha(entry) in base64.b64decode(start['argv'][-1]).decode('utf-16-le')
for name in ('stdout','stderr'):assert sha(F/f'root-lifecycle-controls-r1.{name}.bin')==process[name+'Sha256']
D=F/'root-before-compile-controls-r1';receipt=read(D/'receipt.json');assert receipt['stageSha256']==sha(M) and receipt['entrySha256']==sha(entry)
for k in ['passed','astPassed','cleanupPassed','hostInputsPassed','integerPassed','productionAdmissionPassed','productionInvocationProofPassed']:assert receipt[k] is True
assert receipt['error'] is None and receipt['compilerInvocations']==receipt['nativeCalls']==0 and receipt['oldControlOutputsOverwritten'] is False
for x in receipt['files']:
 p=D/x['path'].replace('\\','/');assert sha(p)==x['sha256'] and p.stat().st_size==x['bytes']
ast=read(D/'ast-controls.json');assert len(ast)==3
for x in ast:assert not x['errors'] and sha(F/x['path'].split('\\')[-1])==x['sha256']
cleanup=read(D/'cleanup-controls.json');host=read(D/'host-fixtures/controls.json');integer=read(D/'integer-controls.json')
for j in [cleanup,host,integer]:assert all(x['rejected'] is True for x in j['faults']) and j['compilerInvocations']==0
assert len(cleanup['faults'])==3 and cleanup['positiveCases']==3 and len(host['faults'])==5 and host['normalPassed'] and host['pass'] and len(integer['faults'])==9 and integer['positiveInt32']==integer['positiveInt64']==2
B=R/'factory/native/windows/round1-seeded-build-v2';H=R/'factory/native/windows/round1-seeded-hosts-v1/shared/host-inputs.ps1'
assert cleanup['helperSha256']==sha(B/'cleanup-decision.ps1') and host['helperSha256']==sha(H) and integer['helperSha256']==sha(B/'control-admission.ps1')
for fresh,old in [(D/'cleanup-controls.json',B/'control-results/cleanup-controls.json'),(D/'integer-controls.json',B/'control-results/integer-controls.json'),(D/'host-fixtures/controls.json',B/'control-results/host-input-controls.json')]:assert sha(fresh)==sha(old)
p=read(B/'control-results/admission-controls.json');assert p['actualGeneratedOutputsPassed'] and p['fixturePositivePassed'] and p['admissionHelperSha256']==sha(B/'control-admission.ps1') and len(p['faults'])==7 and all(x['rejected'] for x in p['faults'])
for x in read(B/'control-results/parse-controls.json'):
 q=R/x['path'].replace('D:\\Claude\\swiftright\\','').replace('\\','/');assert not x['errors'] and sha(q)==x['sha256']
lint=read(B/'control-results/reserved-lint.json');assert lint['pass']
for x in lint['files']:
 q=R/x['path'].replace('D:\\Claude\\swiftright\\','').replace('\\','/');assert not x['reservedAssignments'] and sha(q)==x['sha256']
j={'kind':'independent-lifecycle-precompile-actual-controls','decision':'clear-for-single-compiler-build','sourceStageSha256':sha(M),'sourcePins':35,'entrySha256':sha(entry),'fetchPins':13,'ASTCount':3,'cleanupFaults':3,'hostFaults':5,'integerFaults':9,'originalAdmissionFaults':7,'productionAdmission':'original source/raw helper/output/lint pins replay exact; fresh outputs byte-equal original','actualRootExecutionExitCode':process['exitCode'],'compilerInvocations':0,'nativeCalls':0,'nextAction':'single frozen lifecycle compiler build'}
p=O/'report.json';p.write_text(json.dumps(j,indent=2)+'\n');print(sha(p))
