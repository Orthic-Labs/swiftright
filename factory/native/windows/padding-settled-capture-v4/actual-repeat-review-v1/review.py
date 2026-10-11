from pathlib import Path
import hashlib,json,struct
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/native/windows/padding-settled-capture-v4';A=P/'actual-repeat-r1';O=P/'actual-repeat-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
nfiles=0
for name in ('fetch-actual-repeat-r1.json','fetch-coordinator-repeat-r1.json'):
 f=load(P/name);assert f['scpExit']==0
 for rel,h in f['files'].items():assert sha(R/rel)==h,rel;nfiles+=1
c=load(P/'coordinator-repeat-r1/coordinator.json');assert c['status']=='hold-harness-error' and c['count']==20 and c['lockReleased'] and c['wholeBatchExitConfirmed'] and not c['cleanupErrors']
assert sha(A/'observation.json')==c['compileReceiptHash']=='90f50b3fa049d4b21a0c5ad5eca78d8c024b961aa102fbc345767c151e503365'
assert c['exeHash']=='9ed4e7ed376cf2ad20879e99326291dcad31634156934e69d86094b2685fb5a4' and c['serializerControlSha256']=='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
assert {p.name for p in A.glob('native-*')}=={f'native-{i:02}' for i in range(1,19)}
assert not (A/'dispatch.json').exists() and not (A/'native-observation.json').exists()
rows=[]
for i in range(1,19):
 n=A/f'native-{i:02}';out=load(n/'capture-outcome.json');owned=load(n/'owned-process.json');close=load(n/'owned-close.json');pix=load(n/'native.pixels.json');uia=load(n/'native.uia.json')
 assert out['ownedIdentity']==owned and out['lockOwner']==c['owner']
 for field in ('compileReceiptHash','exeHash','serializerControlSha256'):assert out[field]==c[field]
 assert close['pid']==owned['pid']==pix['pid'] and close['hwnd']==pix['hwnd'] and close['posted'] and not close['activationRequested']
 assert out['cleanup']['confirmedOwnedExit'] and out['cleanup']['kernelExitSignaled'] and out['cleanup']['kernelWaitResult']==0
 assert not out['streamErrors'] and out['rawHashesQualification']=='sealed-raw'
 for state in out['rawStreams']:assert state['sealed'] and state['destinationClosed'] and state['taskStatus']==state['closureTaskStatus']=='RanToCompletion'
 for field,name in [('stdoutSha256','host.stdout.txt'),('stderrSha256','host.stderr.txt')]:assert sha(n/name)==out[field]
 for sample in pix['samples']:
  if 'path' in sample:assert sha(n/sample['path'])==sample['sha256']
 assert pix['printWindowRepeatStable'] and pix['screenRepeatStable'] and not pix['controlledOcclusionQualification']
 assert len([x for x in pix['samples'] if 'path' in x])==4
 for name in ('native.printwindow.png','native.printwindow.repeat.png','native.screen.png','native.screen.repeat.png'):
  raw=(n/name).read_bytes();assert struct.unpack('>II',raw[16:24])==(800,600)
 assert uia['children'][0]['name']=='Box'
 text=(n/'host.stdout.txt').read_text();assert 'FACTORY_RENDERER_READY' in text and 'FACTORY_COMMIT' in text and 'FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' in text
 metrics=[json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('FACTORY_METRICS ')]
 assert any(x['phase']=='first-window-metrics-event' for x in metrics)
 assert (out['primaryError']=='') if i<18 else (out['primaryError']=='Owned renderer child deadline')
 hosterrors=[line for line in text.splitlines() if line.startswith(('FACTORY_RENDER_ERROR','FACTORY_STARTUP_ERROR'))]
 rows.append({'hostErrors':hosterrors,'run':i,'pid':owned['pid'],'hwnd':pix['hwnd'],'primaryError':out['primaryError'],'cleanup':out['cleanup'],'closePostedAt':close['at'],'outcomeSha256':sha(n/'capture-outcome.json'),'metrics':metrics})
last=load(A/'native-18/capture-outcome.json');assert last['preCleanupExitObservation']['kernelWaitResult']==258 and last['preCleanupExitObservation']['hasExitedObserved'] is True
assert last['cleanup']['status']=='signaled-after-exit-observation' and not last['cleanup']['killAttempted']
proof=load(P/'root-first-proof-r1/proof-process.json');assert proof['exitCode']==0
prooftext=(P/'root-first-proof-r1/proof.stdout.bin').read_text();proofdata=json.loads(prooftext);assert proofdata['pass'] is True and proofdata['baseline']=='accepted' and len(proofdata['faults'])==5
report={'verdict':'CONFIRMED_FAILED_PARTIAL_BATCH_WITH_PRIOR_HOST_ERRORS','finding':'capture computes validHost=false on host error but still appends record & continues; runs03/16 errors retained in raw stdout yet primaryError empty. No promotion based on existence of capture assets.','fetchPinsVerified':nfiles,'requestedRuns':20,'startedRuns':18,'priorRawCaptures':17,'priorHostErrorFreeRawCaptures':15,'priorHostErrorRuns':[3,16],'failedRun':18,'notStarted':[19,20],'aggregateSuccessReceiptAbsent':True,'coordinator':c,'run18':{'start':last['ownedIdentity']['startedAt'],'WM_CLOSE':rows[-1]['closePostedAt'],'preCleanup':last['preCleanupExitObservation'],'cleanup':last['cleanup'],'finalStreams':last['rawStreams'],'interpretation':'15-second post-close WaitForExit deadline retained as primary failure. At precleanup Framework HasExited=true while retained kernel wait258; cleanup waited up to5s, obtained kernel0 without killing. Final two streams sealed/closed. No exact exit timestamp or underlying delay cause observed.'},'priorRuns':'17 raw UIA Box captures; runs03/16 contain FactoryOwnedRendererHWNDAmbiguous errors (not clean host observations). 15 have error-free raw host predicates. Each contains +four800x600PNG each, per-run stable method repeats, source/compile/exe/serializer/owner joins &retained kernel exit verified. Batch aborted before aggregate records persisted; no20-success claim.','firstProof':proofdata,'runs':rows,'scope':'Raw source-bound observations; no parity, provider, controlled occlusion or timing qualification','reviewExecution':'Offline Python/hash/source only; no native/remote/compiler actions','inputPins':{str(p.relative_to(R)):sha(p) for p in [P/'fetch-actual-repeat-r1.json',P/'fetch-coordinator-repeat-r1.json',P/'coordinator-repeat-r1/coordinator.json',P/'capture-repeat.ps1',P/'support/cleanup.ps1',P/'root-first-proof-r1/proof.stdout.bin',P/'root-first-proof-r1/proof-process.json']}}
(O/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(sha(O/'report.json'));print(nfiles)
