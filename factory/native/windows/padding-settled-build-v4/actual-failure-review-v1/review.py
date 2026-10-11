from pathlib import Path
import json,hashlib,struct
R=Path('/Volumes/D/claude/swiftright'); P=R/'factory/native/windows/padding-settled-build-v4'; A=P/'root-controls-r1'; S=A/'actual/serializer-control-actual-r1'; O=P/'actual-failure-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
proc=load(A/'controls-process.json'); c=load(S/'compile/observation.json'); script=(P/'run-serializer-control.ps1').read_text()
assert proc['exitCode']==1
for name in ('stdout','stderr'):assert sha(A/f'controls.{name}.bin')==proc[f'{name}Sha256']
assert c['phase']=='compile' and c['exitCode']==0 and c['ownedExited'] is True and c['kernelWait']==0 and not c['timedOut'] and c['streamDrainComplete'] is True and c['error'] is None and c['cleanupError'] is None
for row in c['rawFileHashes']:
 assert sha(S/'compile'/row['path'])==row['hash']['sha256'];assert row['hash']['qualification']=='sealed-raw'
for state in c['rawStreams']:assert state['sealed'] and state['destinationClosed'] and state['taskStatus']=='RanToCompletion' and state['closureTaskStatus']=='RanToCompletion'
assert c['planSha256']==sha(P/'package/plan.json')
assert c['toolSha256']=='1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
assert 'MetricsPayload.swift' in c['argv'] and 'serializer-control\\main.swift' in c['argv']
assert not (S/'run').exists() and not (S/'control.json').exists()
assert b'SERIALIZER_CONTROL_PASS' not in (A/'controls.stdout.bin').read_bytes()
assert 'System.IO.FileStream' in (A/'controls.stderr.bin').read_text()
assert "$source=if($stream.name" in script and script.index('$source=if($stream.name')<script.index(' Assert-Inputs\n return $record')
exe=S/'serializer-control.exe'; raw=exe.read_bytes(); assert raw[:2]==b'MZ'; off=struct.unpack_from('<I',raw,60)[0];assert raw[off:off+4]==b'PE\0\0';pe=struct.unpack_from('<H',raw,off+24+68)[0]
inputs=[P/'run-serializer-control.ps1',P/'root-stage-manifest.json',P/'package/plan.json',P/'package/Sources/FactoryProbe/MetricsPayload.swift',P/'serializer-control/main.swift',A/'controls.ps1',A/'controls-process.json',A/'controls-start.json',A/'controls.stdout.bin',A/'controls.stderr.bin',A/'fetch.json']+list(S.rglob('*'))
pins={str(p.relative_to(R)):{'sha256':sha(p),'bytes':p.stat().st_size} for p in inputs if p.is_file()}
report={'kind':'independent-padding-v4-actual-failure-review','verdict':'CONFIRMED_HARNESS_FAILURE_AFTER_PURE_COMPILE','finding':{'cause':'PowerShell dynamic scope: Invoke-SerializerChild local $source overwritten with BaseStream; post-child Assert-Inputs Get-FileHash $source receives FileStream, fails Resolve-Path before function returns.','observedError':'Resolve-Path D:\\Claude\\System.IO.FileStream','failedStep':'post-compile source verification','serializerRunStarted':False,'serializerPASS':False,'GUIHostCompile':False,'nativeActions':0},'actualCompile':{'pid':c['pid'],'processStartedAt':c['processStartedAt'],'startedAt':c['startedAt'],'finishedAt':c['finishedAt'],'exitCode':0,'kernelWait':0,'ownedExited':True,'rawStreams':'Two exact hash-verified sealed raw streams; completion plus destination closure confirmed','exeSha256':sha(exe),'peSubsystem':pe,'argvAuthority':'Build script constructed receipt; no CIM argv assertion','output':'Empty stdout; stderr only linker library/object creation'},'coordinator':proc,'fetch':'Seven fetch rows exit0 confirms retrieval only; not control success','sourcePins':pins,'reviewExecution':'Offline Python only; no compiler/native/remote execution'}
(O/'report.json').write_text(json.dumps(report,indent=2)+'\n')
print(sha(O/'report.json'))
