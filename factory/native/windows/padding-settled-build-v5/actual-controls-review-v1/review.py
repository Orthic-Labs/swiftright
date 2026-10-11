from pathlib import Path
import hashlib,json,re,struct
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/native/windows/padding-settled-build-v5';A=P/'root-controls-r1';S=A/'actual/serializer-control-actual-r2';O=P/'actual-controls-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
f=load(A/'fetch.json');assert all(x['exitCode']==0 for x in f['rows'])
for rel,row in f['files'].items():
 p=A/'actual'/rel;assert sha(p)==row['sha256'],rel;assert p.stat().st_size==row['bytes'],rel
proc=load(A/'controls-process.json');assert proc['exitCode']==0
for n in ('stdout','stderr'):assert sha(A/f'controls.{n}.bin')==proc[f'{n}Sha256']
text=(A/'controls.stdout.bin').read_text();assert 'V5_HEADLESS_SERIALIZER_AND_BUILDER_PREFLIGHT_PASSED' in text
control=load(S/'control.json');assert control['passed'] is True and control['nativeActions']==0
assert control['planSha256']==sha(P/'package/plan.json')
assert control['sourceSha256']==sha(P/'package/Sources/FactoryProbe/MetricsPayload.swift')=='cde9a9a3a90f52eda4134069f7c6be80ad0d7315689c8e2cdc7ae21deb0f19e1'
assert control['controlSha256']==sha(P/'serializer-control/main.swift')=='7b7b79a0e90c63aa696a7347e6ab975fe6dc811bce96b12a2e3548bf3ef64454'
assert control['exeSha256']==sha(S/'serializer-control.exe')
receipts={}
for phase in ('compile','run'):
 c=load(S/phase/'observation.json');receipts[phase]=c
 assert sha(S/phase/'observation.json')==control[phase+'ReceiptSha256']
 assert c['phase']==phase and c['planSha256']==control['planSha256'] and c['nativeActions']==0
 assert c['exitCode']==0 and c['ownedExited'] is True and c['kernelWait']==0 and not c['timedOut'] and c['streamDrainComplete'] is True
 assert c['error'] is None and c['cleanupError'] is None and c['cleanupAction']=='natural-exit-no-termination'
 assert c['pid']>0 and c['processStartedAt'] and c['startedAt']<c['finishedAt']
 assert c['toolSha256']==control['swiftcSha256' if phase=='compile' else 'exeSha256']
 assert c['cwd'].endswith('serializer-control-actual-r2')
 assert len(c['rawStreams'])==2 and {x['name'] for x in c['rawStreams']}=={'stdout','stderr'}
 for x in c['rawStreams']:assert x['sealed'] and x['destinationClosed'] and x['copyCompleted'] and x['taskStatus']==x['closureTaskStatus']=='RanToCompletion'
 for x in c['rawFileHashes']:assert sha(S/phase/x['path'])==x['hash']['sha256'] and x['hash']['qualification']=='sealed-raw'
assert 'MetricsPayload.swift' in receipts['compile']['argv'] and 'serializer-control\\main.swift' in receipts['compile']['argv']
assert receipts['run']['argv']=='' and receipts['run']['toolPath'].endswith('serializer-control.exe')
out=(S/'run/compile.stdout.bin').read_text();assert sha(S/'run/compile.stdout.bin')==control['stdoutSha256']
assert out.splitlines().count(control['requiredMarker'])==1 and 'SERIALIZER_CONTROL_FAIL' not in out
records=[]
for line in out.splitlines():
 if line.startswith('SERIALIZER_CONTROL_RECORD '):
  _,i,payload=line.split(' ',2);assert int(i)==len(records);records.append(json.loads(payload))
assert len(records)==5 and records[1]['event']['window']==2**64-1
assert records[0]['ownedClient']['logicalHeight']==558.4 and records[0]['ownedClient']['scale']==2.5
assert records[2]['windowMetricsEventSeen'] is False and records[3]['status']=='held-missing-actual-windowMetrics-event'
assert 'SERIALIZER_CONTROL_LEGACY_CGFLOAT_VALID false' in out
scope=load(A/'actual/serializer-scope-controls-r1/controls.json');assert scope['driverSha256']==sha(P/'run-serializer-control.ps1')
assert hashlib.sha256(scope['guardSource'].encode()).hexdigest()==scope['guardSha256']
script=(P/'run-serializer-control.ps1').read_text();assert scope['guardSource'] in script
assert {x['mode'] for x in scope['controls']}=={'pipe-source-shadow','string-source-shadow','wrong-script-payload','wrong-script-tool-hash'}
for x in scope['controls']:assert x.get('passed') is True or x.get('rejected') is True
assert 'Get-FileHash $script:serializerPayloadPath' in script and '$pipeSource=if(' in script and '$source=if(' not in script
fixture=(P/'test-serializer-input-scope.ps1').read_text();assert '[scriptblock]::Create($guard)' in fixture and "$serializerPayloadPath=$pipe; Assert-Inputs" in fixture
raw=(S/'serializer-control.exe').read_bytes();offset=struct.unpack_from('<I',raw,60)[0];assert raw[:2]==b'MZ' and raw[offset:offset+4]==b'PE\0\0';assert struct.unpack_from('<H',raw,offset+24+68)[0]==3
pins={str(p.relative_to(R)):{'sha256':sha(p),'bytes':p.stat().st_size} for p in [A/'fetch.json',A/'controls-process.json',A/'controls.stdout.bin',A/'controls.stderr.bin',P/'run-serializer-control.ps1',P/'preflight.ps1',P/'test-serializer-input-scope.ps1',P/'root-stage-manifest.json',S/'control.json',S/'compile/observation.json',S/'run/observation.json',S/'serializer-control.exe',S/'run/compile.stdout.bin',A/'actual/serializer-scope-controls-r1/controls.json']}
report={'kind':'independent-padding-v5-actual-controls-review','verdict':'CLEAR_HEADLESS_SERIALIZER_AND_BUILDER_PREFLIGHT','findings':[],'fetchFilesVerified':len(f['files']),'compile':{k:receipts['compile'][k] for k in ('pid','processStartedAt','exitCode','kernelWait','ownedExited','streamDrainComplete')},'run':{k:receipts['run'][k] for k in ('pid','processStartedAt','exitCode','kernelWait','ownedExited','streamDrainComplete')},'serializer':{'records':5,'UInt64MaxExact':True,'infinityRejected':'Actual PASS reached only after production serializer rejection-domain assertion','legacyCGFloatJSONValid':False,'exeSha256':control['exeSha256'],'controlSha256':sha(S/'control.json')},'scopeControls':'Two dynamic shadows accepted against script-scoped payload path; wrong payload/tool hash rejected via exact AST-extracted production guard','admission':'Preflight binds actual control, child receipt/raw/tool/exe/source/argv/plan hashes; coordinator completion marker confirms headless gates plus builder PreflightOnly, compilerStarted=false','authority':'Constructed child argv receipts; no CIM argv assertion','nativeQualification':False,'reviewExecution':'Offline Python raw/hash/source replay only; zero compiler/native/remote execution','sourcePins':pins}
(O/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'reportSha256':sha(O/'report.json'),'fetchFiles':len(f['files']),'compilePID':receipts['compile']['pid'],'runPID':receipts['run']['pid']}))
