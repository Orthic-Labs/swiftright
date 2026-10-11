from pathlib import Path
import hashlib,json,base64
ROOT=Path(__file__).resolve().parents[6]
F=ROOT/'factory/native/windows/seed-stack-lifecycle-capture-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def certificate(c):
 assert c['confirmedOwnedExit'] is True and c['kernelExitSignaled'] is True
 assert type(c['kernelWaitResult']) is int and c['kernelWaitResult']==0 and c['exitCertification']=='retained-kernel-handle' and not c['error']
m=read(F/'root-stage-manifest.json');assert sha(F/'root-stage-manifest.json')=='5f6d298bbdd887ab59ae9a13690accb45fccbbaa625cfd699801360a6db20f86'
for x in m['files']:
 p=ROOT/x['path'];assert sha(p)==x['sha256'].removeprefix('sha256:') and p.stat().st_size==x['bytes']
fetch=read(F/'root-lifecycle-capture-controls-complete-r1.json');assert len(fetch['files'])==44 and fetch['scpExit']==0
for p,h in fetch['files'].items():assert sha(ROOT/p)==h
start=read(F/'root-lifecycle-capture-controls-r1-start.json');process=read(F/'root-lifecycle-capture-controls-r1-process.json');script=F/'root-run-controls-r1.ps1'
assert sha(script)==start['scriptSha256'];encoded=base64.b64decode(start['argv'][-1]).decode('utf-16-le');assert start['scriptSha256'] in encoded
for row in m['files']:assert row['sha256'].removeprefix('sha256:') in script.read_text()
assert process['exitCode']==0 and process['startedAt']==start['startedAt']
for name in ('stdout','stderr'):assert sha(F/f'root-lifecycle-capture-controls-r1.{name}.bin')==process[name+'Sha256']
parse=read(F/'root-controls-actual-r1/parse.json')
for x in parse:
 assert not x['errors'];assert sha(F/x['path'].split('\\')[-1])==x['sha256']
ns=read(F/'root-controls-actual-r1/namespace/controls.json');assert len(ns)==7 and all(x['rejected']==(x['name'] not in ('normal','empty')) for x in ns)
close=read(F/'root-controls-actual-r1/owned-close/controls.json');assert len(close)==8 and all(x['rejected']==(x['mode']!='normal') for x in close)
proof=read(F/'root-controls-actual-r1/capture-exit/controls.json');assert len(proof)==28 and all(x['accepted']==(x['mode']=='normal') for x in proof)
cleanup=read(F/'root-controls-actual-r1/cleanup/controls.json');assert all(not x['result']['confirmedOwnedExit'] for x in cleanup if x.get('mode') in ('observed-not-signaled','kernel-wait-failed','timeout','identity-drift'))
seal=read(F/'root-controls-actual-r1/stream-seal/controls.json');timeout=next(x for x in seal if x['mode']=='actual-close-timeout-capture-coordinator-hash-gate');assert timeout['timedOut'] and timeout['hashCallbackCalls']==0
for name in ('captureHash','coordinatorHash'):assert timeout[name]['sha256'] is None and timeout[name]['qualification']=='unqualified'
failed=next(x for x in seal if x['mode']=='failed-flush-successful-dispose-reject-seal');assert failed['rejected'] and failed['state']['destinationClosed'] and not failed['state']['sealed'] and not failed['state']['closure']['flushCompleted']
ordinary=read(F/'root-controls-actual-r1/process-streams/controls.json');certificate(ordinary['cleanup']);assert ordinary['pid']>0 and ordinary['exitCode']==0 and ordinary['createNoWindow']
for x in ordinary['files']:assert sha(F/'root-controls-actual-r1/process-streams'/x['path'])==x['sha256']
assert (F/'root-controls-actual-r1/process-streams/stdout.bin').read_bytes()==b'controlstdout\r\n';assert (F/'root-controls-actual-r1/process-streams/stderr.bin').read_bytes()==b'controlstderr\r\n'
bounds=F/'root-controls-actual-r1/kernel-bounds';summary=read(bounds/'controls.json');assert summary['status']=='passed' and summary['consoleOnly'] and not summary['rendererLoaded']
assert summary['exitMilliseconds']==15000 and summary['streamMilliseconds']==summary['closureMilliseconds']==5000
actual=read(bounds/'actual-streams/controls.json');assert [x['mode'] for x in actual]==['volume','inherit']
for row,size in zip(actual,(393216,65536)):
 certificate(row['cleanup']);assert not row['primaryError'];d=bounds/'actual-streams'/row['mode'];raw=(d/'stdout.bin').read_bytes();assert raw==bytes(33+i%90 for i in range(size));assert (d/'stderr.bin').read_bytes()==b''
 for state in row['rawStreams']:assert state['destinationClosed'] and state['closureTaskStatus']=='RanToCompletion' and state['taskStatus']=='RanToCompletion'
vol,inh=actual;assert all(x['sealed'] and x['copyCompleted'] and x['closure']['flushCompleted'] for x in vol['rawStreams']);certificate(inh['holderCleanup'])
i=inh['initial'];assert i['primaryKernelSignaled'] and i['primaryHasExited'] and not i['writerKernelSignaled'] and not i['stdoutCompletedWithin5000']
d=i['failureDisposition'];assert d['diagnosticBytes']==65536 and d['diagnosticSha256']==sha(bounds/'actual-streams/inherit/stdout.bin') and d['stableAfterSourceSettlement']
for x in d['before']:assert not x['taskIsCompleted'] and not x['destinationClosed']
for x in d['after']:assert x['destinationClosed'] and not x['sealed'] and not x['copyCompleted'] and x['closure']['flushDisposition']=='skipped-pending-copy' and not x['closure']['flushCompleted']
for x in d['afterSourceSettlement']:assert x['taskIsCompleted'] and not x['sealed']
for pair in [('fake-kernel','root-controls-actual-r1/cleanup'),('proof-gates','root-controls-actual-r1/capture-exit'),('closure-hash-gates','root-controls-actual-r1/stream-seal')]:assert sha(bounds/pair[0]/'controls.json')==sha(F/pair[1]/'controls.json')

D=F/'root-controls-actual-r1';overall=read(D/'controls.json');assert overall['status']=='passed' and overall['consoleControlsOnly'] and not overall['rendererLoaded'] and overall['compilerInvocations']==overall['nativeWindows']==0
parent=read(D/'parent-mac-proof/controls.json');assert all(x['rejected']==(x['mode']!='normal') for x in parent)
life=read(D/'lifecycle-binding/controls.json');assert life['status']=='passed' and life['syntheticCompileFixture'] and life['sourceFilesObserved'] and life['compilerInvocations']==life['nativeWindows']==0 and not life['rendererLoaded'];assert len(life['controls'])==32
assert all(x['rejected']==(x['mode']!='normal') for x in life['controls'])
changed=next(x for x in life['controls'] if x['mode']=='actual-changed-main-bytes');assert sha(D/'lifecycle-binding/changed-main.swift')==changed['sha256']
report={'kind':'independent-lifecycle-capture-actual-controls','decision':'clear-for-one-diagnostic-native-single-with-measured-compiler-pins','sourcePins':69,'rawFetchPins':44,'ASTCount':len(parse),'namespaceCount':len(ns),'cleanupCount':len(cleanup),'closeCount':len(close),'exitProofCount':len(proof),'sealCount':len(seal),'parentMacProofCount':len(parent),'lifecycleBindingCount':len(life['controls']),'syntheticCompileFixture':True,'actualConsoleOnly':True,'kernelSignal':'strict raw0 retained results; HasExited-only fault rejects','volumeBytes':393216,'heldEOFBytes':65536,'timeoutHashCallbacks':0,'producerStageSha256':sha(F/'root-stage-manifest.json'),'receiptScope':'Bounded C# primary PID/path/start/argv not serialized; source-bound actual control facts only. Ordinary hidden process full identity joined.','nextAction':'Join independently cleared actual diagnostic compiler/exe pins before one native single'}
p=Path(__file__).parent/'report.json';p.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));print(sha(p))
