"""Read-only custom busy-lock/fetch provenance; no native/remote launch."""
from pathlib import Path
import hashlib,json,re,base64,datetime
REPO=Path(__file__).resolve().parents[6];LANE=REPO/'factory/native/windows/round1-seeded-native-v5';OUT=Path(__file__).resolve().parent;refs={}
def raw(p):
 b=p.read_bytes();refs[str(p.relative_to(REPO))]={'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)};return b
def sha(p):return hashlib.sha256(raw(p)).hexdigest()
def load(p):return json.loads(raw(p).decode('utf-8-sig'))
def check(v,m):
 if not v:raise ValueError(m)
def time(s):return datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
root=LANE/'single-custom-layout-r1';batch=load(root/'batch.json');dispatch=load(root/'replays/run-001/dispatch.json');entry=LANE/'root-single-custom-layout-r1.ps1';start=load(LANE/'root-single-custom-r1-start.json');process=load(LANE/'root-single-custom-r1-process.json');early=load(LANE/'root-single-custom-early-output-scp.json');note=load(LANE/'root-single-custom-early-fetch-note.json');complete=load(LANE/'root-single-custom-complete-r1.json')
check(batch['requested']==batch['attempted']==1 and len(batch['rows'])==1 and batch['retry'] is False and batch['status']=='hold-batch-error','batch')
check(batch['rows'][0]['status']=='hold-desktop-busy' and batch['rows'][0]['dispatchHash']==sha(root/'replays/run-001/dispatch.json'),'dispatch join')
check(dispatch['status']=='hold-desktop-busy' and dispatch['lockAcquired'] is False and dispatch['lockReleased'] is False and dispatch['windowedDispatch'] is False and dispatch['taskRetained'] is False,'foreign lock boundary')
check(not dispatch['cleanupErrors'] and not dispatch['error'],'dispatch error')
wait=dispatch['waitObservations'];check(wait and all(r['state']=='r8-11 lead' and r['acquired'] is False for r in wait),'actual busy observations')
check(all(time(a['at'])<time(b['at']) for a,b in zip(wait,wait[1:])),'wait order')
check(sha(entry)==start['scriptSha256'],'entry pin');decoded=base64.b64decode(start['argv'][-1]).decode('utf-16-le');check(start['scriptRemotePath'] in decoded and start['scriptSha256'] in decoded,'actual encoded invocation')
entry_bytes=raw(entry).decode();check("-Case 'custom-layout'" in entry_bytes and '-Count 1' in entry_bytes,'exact entry scope')
check(process['startedAt']==start['startedAt'] and process['exitCode']==1,'process outcome')
check(sha(LANE/'root-single-custom-r1.stdout.bin')==process['stdoutSha256'] and sha(LANE/'root-single-custom-r1.stderr.bin')==process['stderrSha256'],'process streams')
check(early['scpExit']==0 and early['files']=={} and note['processStillRunning'] is True and note['filesFetched']==0 and note['remoteMutation'] is False,'early empty fetch')
check(time(process['startedAt'])<time(early['startedAt'])<time(early['finishedAt'])<time(process['finishedAt'])<time(complete['startedAt'])<time(complete['finishedAt']),'process/fetch ordering')
check(complete['scpExit']==0 and len(complete['files'])==2,'final two files')
check({str(p.relative_to(REPO)) for p in root.rglob('*') if p.is_file()}==set(complete['files']),'exact fetched membership')
for path,h in complete['files'].items():check(sha(REPO/path)==h,'fetch bytes')
contract=load(LANE/'contract.json');check(sha(LANE/'contract.json')==batch['contractHash'],'contract');route=next(r for r in contract['hosts'] if r['label']=='custom-layout');host=REPO/'factory/native/windows/round1-seeded-hosts-v1/custom-layout';obs=load(host/'build-actual-v2-r1/observation.json');check(sha(host/'build-actual-v2-r1/observation.json')==batch['compileReceiptHash'] and obs['exeSha256']==batch['exeHash'] and sha(host/'build-actual-v2-r1/FactoryProbe.exe')==batch['exeHash'],'measured input route')
for n in ['root-single-custom-early-output-scp.stdout.bin','root-single-custom-early-output-scp.stderr.bin','root-single-custom-complete-r1.stdout.bin','root-single-custom-complete-r1.stderr.bin','run-repeat.ps1','run-batch.ps1']:raw(LANE/n)
report={'decision':'CLEAR-BUSY-LOCK-DIAGNOSTIC-JOINS','case':'custom-layout','requested':1,'dispatchAttempts':1,'nativeLaunches':0,'captured':0,'retry':False,'foreignOwnerObserved':'r8-11 lead','waitObservations':len(wait),'waitFirst':wait[0]['at'],'waitLast':wait[-1]['at'],'lockAcquired':False,'lockReleased':False,'foreignLockMutationClaim':False,'earlyFetch':'successful SCP while process still running; zero files, not final outcome','finalFetchFiles':2,'processExitCode':1,'nativeParity':'hold','currentLockState':'no independent remote observation; archived wait states only','files':refs}
p=OUT/'single-custom-layout-r1-busy.json';check(not p.exists(),'fresh report');p.write_text(json.dumps(report,indent=2)+'\n')
