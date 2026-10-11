from pathlib import Path
import hashlib,json,base64
ROOT=Path(__file__).resolve().parents[5]
F=ROOT/'factory/native/windows/round1-seeded-native-v5'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def certificate(c):
 assert c['confirmedOwnedExit'] is True and c['kernelExitSignaled'] is True
 assert type(c['kernelWaitResult']) is int and c['kernelWaitResult']==0 and c['exitCertification']=='retained-kernel-handle' and not c['error']
m=read(F/'root-stage-manifest.json');assert sha(F/'root-stage-manifest.json')=='817ee4713257d0bafc802f867cf4b0626b4b5ce07d9fade812c50f4b10149ebb'
for x in m['files']:
 p=ROOT/x['path'];assert sha(p)==x['sha256'].removeprefix('sha256:') and p.stat().st_size==x['bytes']
fetch=read(F/'root-control-output-scp.json');assert len(fetch['files'])==39 and all(t['exitCode']==0 and not t['stderr'] for t in fetch['transfers'])
for p,h in fetch['files'].items():assert sha(ROOT/p)==h
start=read(F/'root-controls-r1-start.json');process=read(F/'root-controls-r1-process.json');script=F/'root-controls-file-r1.ps1'
assert sha(script)==start['scriptSha256'];encoded=base64.b64decode(start['argv'][-1]).decode('utf-16-le');assert start['scriptSha256'] in encoded
for row in m['files']:assert row['sha256'].removeprefix('sha256:') in script.read_text()
assert process['exitCode']==0 and process['startedAt']==start['startedAt']
for name in ('stdout','stderr'):assert sha(F/f'root-controls-r1.{name}.bin')==process[name+'Sha256']
parse=read(F/'root-parse-actual-r1.json')
for x in parse:
 assert not x['errors'];assert sha(F/x['path'].split('\\')[-1])==x['sha256']
ns=read(F/'root-namespace-actual-r1/controls.json');assert len(ns)==7 and all(x['rejected']==(x['name'] not in ('normal','empty')) for x in ns)
close=read(F/'root-close-actual-r1/controls.json');assert len(close)==8 and all(x['rejected']==(x['mode']!='normal') for x in close)
proof=read(F/'root-exit-proof-actual-r1/controls.json');assert len(proof)==28 and all(x['accepted']==(x['mode']=='normal') for x in proof)
cleanup=read(F/'root-cleanup-actual-r1/controls.json');assert all(not x['result']['confirmedOwnedExit'] for x in cleanup if x.get('mode') in ('observed-not-signaled','kernel-wait-failed','timeout','identity-drift'))
seal=read(F/'root-stream-actual-r1/controls.json');timeout=next(x for x in seal if x['mode']=='actual-close-timeout-capture-coordinator-hash-gate');assert timeout['timedOut'] and timeout['hashCallbackCalls']==0
for name in ('captureHash','coordinatorHash'):assert timeout[name]['sha256'] is None and timeout[name]['qualification']=='unqualified'
failed=next(x for x in seal if x['mode']=='failed-flush-successful-dispose-reject-seal');assert failed['rejected'] and failed['state']['destinationClosed'] and not failed['state']['sealed'] and not failed['state']['closure']['flushCompleted']
ordinary=read(F/'root-process-streams-actual-r1/controls.json');certificate(ordinary['cleanup']);assert ordinary['pid']>0 and ordinary['exitCode']==0 and ordinary['createNoWindow']
for x in ordinary['files']:assert sha(F/'root-process-streams-actual-r1'/x['path'])==x['sha256']
assert (F/'root-process-streams-actual-r1/stdout.bin').read_bytes()==b'controlstdout\r\n';assert (F/'root-process-streams-actual-r1/stderr.bin').read_bytes()==b'controlstderr\r\n'
bounds=F/'root-kernel-bounds-actual-r1';summary=read(bounds/'controls.json');assert summary['status']=='passed' and summary['consoleOnly'] and not summary['rendererLoaded']
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
for pair in [('fake-kernel','root-cleanup-actual-r1'),('proof-gates','root-exit-proof-actual-r1'),('closure-hash-gates','root-stream-actual-r1')]:assert sha(bounds/pair[0]/'controls.json')==sha(F/pair[1]/'controls.json')
report={'kind':'independent-seeded-native-v5-actual-controls-review','decision':'clear-for-source-bound-native-singles','producerStageSha256':sha(F/'root-stage-manifest.json'),'fetchSha256':sha(F/'root-control-output-scp.json'),'sourcePins':24,'actualFetchPins':39,'ASTCount':len(parse),'namespaceCount':len(ns),'cleanupCount':len(cleanup),'closeCount':len(close),'proofCount':len(proof),'sealCount':len(seal),'actualConsoleRows':3,'volumeBytes':393216,'heldEOFBytes':65536,'timeoutHashCallbacks':0,'actualKernelWaits':'primary &holder wait0; HasExited without signal faults rejected','rawQualification':'completed volume sealed; heldEOF partial/unsealed after closed destination &stable settlement','receiptScope':'Ordinary hidden PowerShell PID/path/start/argv recorded. Bounded C# primary/holder source execution &kernel results recorded; primary PID/path/start/argv absent from results, holder.pid retained separately. No invented identity joins.','nextAction':'Run frozen5 fresh source-bound native singles','qualification':'controls only; no native parity/timing admission'}
p=Path(__file__).parent/'actual-controls-review-v1.json';p.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));print('reportSha256',sha(p))
