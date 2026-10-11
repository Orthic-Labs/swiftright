"""Read-only failed capture byte/kernel/stream joins; no native or process launch."""
from pathlib import Path
import json,hashlib,struct,re,datetime
REPO=Path(__file__).resolve().parents[6];LANE=REPO/'factory/native/windows/round1-seeded-native-v5';OUT=Path(__file__).resolve().parent;ROOT=LANE/'single-stack-overlay-r1';HOST=REPO/'factory/native/windows/round1-seeded-hosts-v1/stack-overlay';refs={}
def raw(p):
 b=p.read_bytes();refs[str(p.relative_to(REPO))]={'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)};return b
def sha(p):return hashlib.sha256(raw(p)).hexdigest()
def load(p):return json.loads(raw(p).decode('utf-8-sig'))
def check(v,msg):
 if not v:raise ValueError(msg)
def scope(d):check(d['nativeParity']=='hold' and d['frozenTupleBound'] is False and d['closureBinding'] is None,'scope')
def ticks(s):
 m=re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(Z|[+-]\d\d:\d\d)',s);check(m is not None,'ISO time');d=datetime.datetime.fromisoformat(m[1]+m[3].replace('Z','+00:00'));epoch=datetime.datetime(1970,1,1,tzinfo=datetime.timezone.utc);delta=d-epoch;return (delta.days*86400+delta.seconds)*10000000+int((m[2] or '').ljust(7,'0'))
batch=load(ROOT/'batch.json');check(batch['requested']==batch['attempted']==1 and batch['retry'] is False and batch['status']=='hold-batch-error' and len(batch['rows'])==1,'failed batch');scope(batch)
check({p.name for p in (ROOT/'replays').iterdir() if p.is_dir()}=={'run-001'},'no retries')
route=next(x for x in load(LANE/'contract.json')['hosts'] if x['label']=='stack-overlay');check(sha(LANE/'contract.json')==batch['contractHash'],'contract')
run=ROOT/'replays/run-001';native=run/'native-01';plan=load(HOST/'package/plan.json');obs=load(HOST/'build-actual-v2-r1/observation.json');exe=raw(HOST/'build-actual-v2-r1/FactoryProbe.exe');eh=hashlib.sha256(exe).hexdigest()
check(sha(HOST/'package/plan.json')==route['planHash']==obs['planSha256'],'plan');check(sha(HOST/'build-actual-v2-r1/observation.json')==batch['compileReceiptHash'],'compile');check(eh==obs['exeSha256']==batch['exeHash'],'exe');pe=struct.unpack_from('<I',exe,0x3c)[0];check(struct.unpack_from('<H',exe,pe+24+68)[0]==2,'GUI PE')
check(obs['exitCode']==0 and obs['timedOut'] is False and obs['ownedExited'] is True,'compile outcome')
check(sha(run/'plan.json')==route['planHash'] and sha(run/'observation.json')==batch['compileReceiptHash'],'copied raw metadata')
for b in plan['sourceBindings']:
 source=HOST/'package'/b['path'];check('sha256:'+sha(source)==b['sha256'],'host source')
 if b['path']=='Package.swift' or b['path'].startswith('Sources/'):check(raw(source)==raw(run/b['path']),'copied consumed source')
proof=load(LANE/'proof/source-join.json');check(sha(LANE/'proof/source-join.json')=='9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3','Mac proof');mac=next(x for x in proof['cases'] if x['block']=='stack-overlay');check(mac['case']==plan['case'] and mac['witnessHash']==plan['sourceHash'] and len(mac['runs'])==20,'Mac20 source')
dispatch=load(run/'dispatch.json');task=load(run/'task-result.json');outcome=load(native/'capture-outcome.json');owned=load(native/'owned-process.json');close=load(native/'owned-close.json');pixels=load(native/'native.pixels.json');uia=load(native/'native.uia.json');launch=load(native/'launch-observation.json')
check(sha(run/'dispatch.json')==batch['rows'][0]['dispatchHash'],'dispatch');scope(dispatch)
check(task['error']==outcome['primaryError']=='Owned renderer child deadline' and task['status']==dispatch['status']=='hold-harness-error','failure retained')
check(outcome['ownedIdentity']==owned and owned['path']==obs['exePath'] and type(owned['pid'])is int,'owned identity')
check(outcome['sourceHash']==plan['sourceHash'] and outcome['compileReceiptHash']==batch['compileReceiptHash'] and outcome['exeHash']==eh and outcome['lockOwner']==dispatch['owner'],'outcome lineage')
check(outcome['macSourceProofHash']=='9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3','outcome Mac proof')
check(pixels['pid']==close['pid']==owned['pid'] and pixels['hwnd']==close['hwnd']==launch['ownedWindow'],'HWND/PID');check(close['message']==16 and close['posted'] is True and close['activationRequested'] is False,'WM_CLOSE')
pre=outcome['preCleanupExitObservation'];cleanup=outcome['cleanup'];check(type(pre['kernelWaitResult'])is int and pre['kernelWaitResult']==258 and pre['hasExitedObserved'] is True,'actual unsignaled/HasExited discrepancy')
check(cleanup['kernelWaitResult']==0 and type(cleanup['kernelWaitResult'])is int and cleanup['kernelExitSignaled'] is True and cleanup['confirmedOwnedExit'] is True and cleanup['exitCertification']=='retained-kernel-handle' and cleanup['killAttempted'] is False and cleanup['status']=='signaled-after-exit-observation','actual kernel cleanup')
check(not cleanup['error'] and not outcome['streamErrors'],'cleanup errors')
check(len(pre['rawStreams'])==len(outcome['rawStreams'])==2,'stream count')
for s in pre['rawStreams']:check(s['copyCompleted'] is False and s['sealed'] is False and s['hashQualification']=='diagnostic-partial','pre cleanup stream state')
for s in outcome['rawStreams']:
 check(s['copyCompleted'] is True and s['destinationClosed'] is True and s['sealed'] is True and s['hashQualification']=='sealed-raw' and s['taskStatus']=='RanToCompletion','terminal streams')
 c=s['closure'];check(c['deadlineMilliseconds']==5000 and c['flushCompleted'] is True and c['destinationClosed'] is True and c['completedWithinDeadline'] is True and c['deadlineExpired'] is False and not c['error'],'closure')
check(outcome['rawHashesQualification']=='sealed-raw','hash scope')
check(sha(native/'host.stdout.txt')==outcome['stdoutSha256'] and sha(native/'host.stderr.txt')==outcome['stderrSha256'],'stream bytes')
check(dispatch['lockAcquired'] is True and dispatch['lockReleased'] is True and dispatch['lockRetainedForUnconfirmedOwnedExit'] is False and not dispatch['cleanupErrors'],'lock release after signaled cleanup')
check(not (run/'native-observation.json').exists(),'no completed capture receipt')
check(ticks(owned['startedAt'])<ticks(close['at'])<ticks(pre['at'])<ticks(task['finishedAt']),'time ordering')
check(ticks(task['finishedAt'])-ticks(pre['at'])<50000000,'cleanup+terminal streams+task completion within5 seconds')
stdout=raw(native/'host.stdout.txt').decode('utf-8-sig');check('FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' in stdout and 'FACTORY_COMMIT version=' in stdout,'host logs')
ready=re.search(r'FACTORY_RENDERER_READY scale=([\d.]+) width=(\d+) height=(\d+) hwnd=(\d+) pid=(\d+) thread=(\d+) dpi=(\d+) metricsSource=owned-client-rect',stdout);check(ready and int(ready[4])==owned['pid'] if False else ready is not None,'ready');check(int(ready[4])==pixels['hwnd'] and int(ready[5])==owned['pid'] and int(ready[2])==pixels['width'] and int(ready[3])==pixels['height'],'ready actual metric joins')
for sample in pixels['samples']:
 if 'path'in sample:check(sha(native/sample['path'])==sample['sha256'],'pixel hash')
fetch=LANE/'root-single-stack-output-scp.json';f=load(fetch);check(f['scpExit']==0 and len(f['files'])==33,'fetch')
for path,h in f['files'].items():check(sha(REPO/path)==h,'fetched raw hash')
for p in [LANE/'cleanup.ps1',LANE/'capture-repeat.ps1',LANE/'run-repeat.ps1',LANE/'stream-seal.ps1']:raw(p)
report={'decision':'CLEAR-ACTUAL-FAILED-OBSERVATION-JOINS','requested':1,'attempted':1,'completedCaptures':0,'cause':'unproven','primaryError':outcome['primaryError'],'case':plan['case'],'ownedIdentity':owned,'preCleanupKernelWait':258,'preCleanupHasExited':True,'cleanupKernelWait':0,'retainedKernelExitCertified':True,'killAttempted':False,'streams':'both completed/sealed/destination closed after cleanup','cleanupToTaskFinished100ns':ticks(task['finishedAt'])-ticks(pre['at']),'lockReleasedReportedAfterCertifiedExit':True,'WM_CLOSE':close,'UIAChildrenAvailable':len(uia['children']),'pixelsAvailableDiagnosticOnly':True,'nativeParity':'hold','semanticQualification':False,'foregroundUnchangedClaim':False,'files':refs}
p=OUT/'single-stack-overlay-r1-failed.json';check(not p.exists(),'fresh output');p.write_text(json.dumps(report,indent=2)+'\n')
