"""Offline immutable preference deadline/ownership forensic replay."""
from pathlib import Path
import json,hashlib
P=Path(__file__).resolve().parent.parent.with_name('round1-native-v5');R=P.parents[3]
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def j(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def check():
 t=j(P/'root-repeat-preference-output-scp.json');assert t['scpExit']==0
 for f,pin in t['files'].items():assert h(R/f)==pin,f
 b=P/'repeat-preference-key-r1';run=b/'replays/run-001';n=run/'native-01';batch=j(b/'batch.json');d=j(run/'dispatch.json');config=j(run/'config.json');task=j(run/'task-result.json');out=j(n/'capture-outcome.json');own=j(n/'owned-process.json');coordinator=j(n/'coordinator-cleanup.json');plan=j(run/'plan.json');compile=j(run/'observation.json')
 assert batch['requested']==20 and batch['attempted']==1 and batch['status']=='hold-batch-error' and not batch['retry'] and len(list((b/'replays').iterdir()))==1
 assert h(run/'dispatch.json')==batch['rows'][0]['dispatchHash']
 assert d['status']==task['status']=='hold-harness-error' and d['lockAcquired'] and d['lockReleased'] and not d['lockRetainedForUnconfirmedOwnedExit'] and not d['cleanupErrors']
 assert task['error']==out['primaryError']=='Renderer window deadline'
 assert out['cleanup']=={'confirmedOwnedExit':True,'killAttempted':True,'status':'killed-owned-handle','error':''} and not out['streamErrors']
 assert own==out['ownedIdentity'] and out['lockOwner']==config['owner']==d['owner']
 assert out['compileReceiptHash']==config['compileReceiptHash']==batch['compileReceiptHash']==h(run/'observation.json')
 assert out['exeHash']==config['exeHash']==batch['exeHash']==compile['exeSha256'] and own['path']==compile['exePath']
 assert coordinator['status']=='capture-retained-handle-exit-proof' and coordinator['confirmedOwnedExit'] and coordinator['outcomeHash']==h(n/'capture-outcome.json')
 for name in ['stdout','stderr']:assert h(n/('host.'+name+'.txt'))==out[name+'Sha256']
 assert (n/'host.stdout.txt').read_bytes()==b''
 assert (n/'host.stderr.txt').read_text().strip()=='[swiftright-render] SetProcessDpiAwarenessContext(PER_MONITOR_AWARE_V2) -> 1'
 assert not (run/'native-observation.json').exists() and not (n/'owned-close.json').exists() and not (n/'native.uia.json').exists() and not list(n.glob('*.png'))
 assert compile==j(R/'factory/native/windows/round1-next-hosts-v1/preference-key/build-actual-v2-r1/observation.json') and compile['exitCode']==0 and compile['ownedExited'] and not compile['timedOut']
 exe=R/'factory/native/windows/round1-next-hosts-v1/preference-key/build-actual-v2-r1/FactoryProbe.exe';assert h(exe)==out['exeHash']
 for bind in plan['sourceBindings']:
  f=run/bind['path']
  if not f.exists():f=R/'factory/native/windows/round1-next-hosts-v1/preference-key/package'/bind['path']
  assert h(f)==bind['sha256'].removeprefix('sha256:')
 assert out['sourceHash']==plan['sourceHash']==compile['sourceHash']
 return {'status':'preserved-preference-failure-consistent','transferredPins':len(t['files']),'requested':20,'attempted':1,'successfulObservations':0,'failure':'Renderer window deadline; empty stdout; stderr contains only successful DPI-awareness call','ownership':'Exact retained owned PID43196 killed/confirmed exited; zero stream errors; coordinator full retained-proof receipt joins & exact owner lock released','compileReceiptHash':h(run/'observation.json'),'actualExeHash':h(exe),'cause':'No deeper renderer/runtime cause established by retained output','nativeParity':'hold','nativeRunsByReviewer':0,'producerEdits':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
