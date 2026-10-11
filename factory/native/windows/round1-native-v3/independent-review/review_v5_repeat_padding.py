"""Independent offline 20-run observational closure replay. No native execution."""
from pathlib import Path
import hashlib,json
P=Path(__file__).resolve().parent.parent.with_name('round1-native-v5');R=P.parents[3]
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def j(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def check():
 t=j(P/'root-repeat-padding-output-scp.json');assert t['scpExit']==0
 for path,pin in t['files'].items():assert h(R/path)==pin,path
 b=P/'repeat-padding-frame-r1';batch=j(b/'batch.json');contract=j(P/'contract.json');assert batch['contractHash']==h(P/'contract.json')
 assert batch['status']=='completed-20-observational' and batch['requested']==batch['attempted']==20 and not batch['retry'] and not batch['error']
 runs=sorted((b/'replays').iterdir());assert [x.name for x in runs]==['run-%03d'%i for i in range(1,21)] and len(batch['rows'])==20
 host=next(x for x in contract['hosts'] if x['label']=='padding-frame');owners=set();pids=set();starts=set();pwhashes=set();uiah=set();closeTimes=[];foregroundZero=[]
 exe=R/'factory/native/windows/round1-next-hosts-v1/padding-frame/build-actual-v2-r1/FactoryProbe.exe';assert h(exe)==batch['exeHash']
 archive=R/'factory/native/windows/staged-renderer-byte-archive-v1/swiftright_render.dll.bin';renderer=h(archive);assert archive.stat().st_size==11885056
 for row,run in zip(batch['rows'],runs):
  n=run/'native-01';d=j(run/'dispatch.json');config=j(run/'config.json');task=j(run/'task-result.json');plan=j(run/'plan.json');c=j(run/'observation.json');o=j(run/'native-observation.json');out=j(n/'capture-outcome.json');own=j(n/'owned-process.json');close=j(n/'owned-close.json');pix=j(n/'native.pixels.json');launch=j(n/'launch-observation.json');uia=j(n/'native.uia.json')
  assert row['run']==run.name and row['dispatchHash']==h(run/'dispatch.json') and d['status']==task['status']==row['status']=='captured-single-observational-uia-printwindow'
  assert d['lockAcquired'] and d['lockReleased'] and not d['lockRetainedForUnconfirmedOwnedExit'] and not d['error'] and not d['cleanupErrors']
  assert d['owner']==config['owner']==out['lockOwner'];owners.add(d['owner']);pids.add(own['pid']);starts.add(own['startedAt'])
  assert config['package']==host['package'] and h(run/'plan.json')==host['planHash']==c['planSha256']
  assert h(run/'observation.json')==batch['compileReceiptHash']==config['compileReceiptHash']==o['compileReceiptHash']==out['compileReceiptHash']
  assert c==j(R/'factory/native/windows/round1-next-hosts-v1/padding-frame/build-actual-v2-r1/observation.json')
  assert c['exeSha256']==batch['exeHash']==config['exeHash']==o['exeSha256']==out['exeHash']
  for key in ['sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','rendererSha256']:assert plan[key]==c[key]==o[key]
  assert renderer==plan['rendererSha256']
  for bind in plan['sourceBindings']:
   f=run/bind['path']
   if not f.exists():f=R/'factory/native/windows/round1-next-hosts-v1/padding-frame/package'/bind['path']
   assert h(f)==bind['sha256'].removeprefix('sha256:')
  assert h(run/'runtime-source-tree.json')==plan['runtimeSourceTreeHash'].removeprefix('sha256:') and h(run/'runtime-source-receipt.json')==plan['runtimeSourceReceiptHash'].removeprefix('sha256:')
  assert out['ownedIdentity']==own and own['path']==c['exePath'] and out['sourceHash']==plan['sourceHash']
  assert not out['primaryError'] and not out['streamErrors'] and out['cleanup']['confirmedOwnedExit'] and not out['cleanup']['killAttempted'] and out['cleanup']['status']=='already-exited'
  assert close['pid']==own['pid']==pix['pid'] and close['hwnd']==pix['hwnd']==launch['ownedWindow'] and close['message']==16 and close['messageName']=='WM_CLOSE' and close['posted'] and not close['activationRequested'];closeTimes.append(close['at'])
  assert {x['path'] for x in o['files']}=={f.name for f in n.iterdir() if f.is_file()} and len(o['files'])==12
  for x in o['files']:assert h(n/x['path'])==x['sha256']
  for name in ['stdout','stderr']:assert h(n/('host.'+name+'.txt'))==out[name+'Sha256']
  raw=(n/'host.stdout.txt').read_text()
  assert all(x in raw for x in ['FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto','FACTORY_RENDERER_READY','FACTORY_COMMIT','FACTORY_RETAINED_RUN text=Box']) and 'FACTORY_RENDER_ERROR' not in raw and 'FACTORY_STARTUP_ERROR' not in raw
  assert o['hostValid'] and o['exitCode']==0 and not o['probeForegroundAtCapture'] and launch['foregroundBefore']==o['foregroundBeforeLaunch'] and launch['foregroundAfter']==o['foregroundAfterWindow'] and launch['ownedWindow']!=launch['foregroundBefore']
  if launch['foregroundAfter']==0:foregroundZero.append(run.name)
  assert launch['ownedWindow']!=launch['foregroundAfter']
  assert pix['printWindowFlags']==3 and pix['width']==800 and pix['height']==600 and pix['printWindowRepeatStable']
  for x in pix['samples']:
   if 'path' in x:assert h(n/x['path'])==x['sha256']
  assert h(n/'native.printwindow.png')==h(n/'native.printwindow.repeat.png');pwhashes.add(h(n/'native.printwindow.png'));uiah.add(h(n/'native.uia.json'))
  assert uia['name']=='Alchemist FactoryProbe' and uia['children'][0]['name']=='Box' and uia['children'][0]['automationId']=='Root/#0/Modified/Modified/Text'
  assert o['nativeParity']==pix['nativeParity']==batch['nativeParity']=='hold' and not o['frozenTupleBound'] and not pix['controlledOcclusionQualification']
 assert len(owners)==len(starts)==20 and len(pids)==20 and len(pwhashes)==1 and len(uiah)==1
 assert closeTimes==sorted(closeTimes)
 return {'status':'padding20-source-bound-observations-clear','transferredPins':len(t['files']),'distinctOwners':len(owners),'distinctOwnedPIDs':len(pids),'distinctStarts':len(starts),'successfulObservations':20,'eachNativeFileClosure':12,'uniquePrintWindowHashes':sorted(pwhashes),'uniqueUIAHashes':sorted(uiah),'actualRendererByteHash':renderer,'actualExeByteHash':h(exe),'compileReceiptHash':batch['compileReceiptHash'],'closeExit':'All20 exact targeted WM_CLOSE, retained already-exited/no kill, zero raw errors, acquired+released exact owner locks','foregroundZeroAfterWindowRuns':foregroundZero,'scope':'Observational repeatability only; no timing/parity qualification or unchanged-foreground inference','nativeRunsByReviewer':0,'producerEdits':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
