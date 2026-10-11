"""Offline source-bound observational receipt replay; no native parity inference."""
from pathlib import Path
import json,hashlib,struct
P=Path(__file__).resolve().parent.parent.with_name("round1-native-v5");R=P.parents[3]
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def j(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def check():
 t=j(P/'root-single-stack-output-scp.json');assert t['scpExit']==0
 for path,pin in t['files'].items():assert h(R/path)==pin,path
 b=P/'single-stack-overlay-r1';run=b/'replays/run-001';n=run/'native-01';batch=j(b/'batch.json')
 assert batch['status']=='completed-1-observational' and batch['requested']==batch['attempted']==1 and not batch['retry']
 assert len(list((b/'replays').iterdir()))==1
 config=j(run/'config.json');d=j(run/'dispatch.json');task=j(run/'task-result.json');plan=j(run/'plan.json');c=j(run/'observation.json');o=j(run/'native-observation.json');out=j(n/'capture-outcome.json');pix=j(n/'native.pixels.json');owned=j(n/'owned-process.json');launch=j(n/'launch-observation.json')
 assert h(run/'dispatch.json')==batch['rows'][0]['dispatchHash']
 assert d['status']==task['status']==batch['rows'][0]['status']=='captured-single-observational-uia-printwindow'
 assert d['lockAcquired'] and d['lockReleased'] and not d['lockRetainedForUnconfirmedOwnedExit'] and not d['error'] and not d['cleanupErrors']
 assert d['owner']==config['owner'] and ' ' in d['owner']
 assert h(run/'observation.json')==batch['compileReceiptHash']==config['compileReceiptHash']==o['compileReceiptHash']
 assert c['exitCode']==0 and c['ownedExited'] and not c['timedOut']
 assert h(run/'plan.json')==c['planSha256']=='8c89995f6eb23939a365d068b0eb3c8d407194a5cf1f720b9bdc71f01066e1e2'
 for key in ['sourceHash','rendererSha256','runtimeSourceCommit','runtimeSourceTreeHash']:assert c[key]==plan[key]==o[key]
 assert c['exeSha256']==batch['exeHash']==config['exeHash']==o['exeSha256']
 exe=R/'factory/native/windows/round1-stack-layout-repair-v1/build-actual-r1/FactoryProbe.exe';assert h(exe)==c['exeSha256']
 eb=exe.read_bytes();off=struct.unpack_from('<I',eb,60)[0];assert struct.unpack_from('<H',eb,off+24+68)[0]==2
 assert c==j(R/'factory/native/windows/round1-stack-layout-repair-v1/build-actual-r1/observation.json')
 for bind in plan['sourceBindings']:
  f=run/bind['path']
  if not f.exists():f=R/'factory/native/windows/round1-stack-layout-repair-v1/stack-overlay/package'/bind['path']
  assert h(f)==bind['sha256'].removeprefix('sha256:')
 assert h(run/'runtime-source-tree.json')==plan['runtimeSourceTreeHash'].removeprefix('sha256:')
 assert not out['primaryError'] and not out['streamErrors'] and out['cleanup']['confirmedOwnedExit'] and out['cleanup']['status']=='already-exited'
 for name in ['stdout','stderr']:assert h(n/('host.'+name+'.txt'))==out[name+'Sha256']
 assert {x['path'] for x in o['files']}=={f.name for f in n.iterdir() if f.is_file()}
 for x in o['files']:assert h(n/x['path'])==x['sha256']
 raw=(n/'host.stdout.txt').read_text()
 for text in ['FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto','FACTORY_RENDERER_READY','FACTORY_COMMIT','kind=Rectangle','kind=Circle']:assert text in raw
 assert 'FACTORY_RENDER_ERROR' not in raw and 'FACTORY_STARTUP_ERROR' not in raw and o['hostValid'] and o['exitCode']==0
 assert owned['pid']==pix['pid'] and owned['path']==c['exePath'] and launch['ownedWindow']==pix['hwnd']
 assert launch['foregroundBefore']==launch['foregroundAfter']==o['foregroundBeforeLaunch']==o['foregroundAfterWindow'] and launch['ownedWindow']!=launch['foregroundBefore'] and not o['probeForegroundAtCapture']
 assert pix['printWindowFlags']==3 and pix['width']==800 and pix['height']==600
 for x in pix['samples']:
  if 'path' in x:assert h(n/x['path'])==x['sha256']
 assert pix['printWindowRepeatStable'] and pix['screenRepeatStable'] and not pix['methodsEqual'] and not pix['controlledOcclusionQualification']
 uia=j(n/'native.uia.json');assert uia['controlType']=='ControlType.Window' and uia['name']=='Alchemist FactoryProbe' and uia['children'][0]['name']=='+'
 assert o['nativeParity']==pix['nativeParity']==batch['nativeParity']=='hold' and not o['frozenTupleBound']
 close=j(n/'owned-close.json')
 assert close['hwnd']==pix['hwnd'] and close['pid']==owned['pid'] and close['message']==16 and close['messageName']=='WM_CLOSE' and close['posted'] and not close['activationRequested']
 assert out['ownedIdentity']==owned and out['lockOwner']==d['owner'] and out['compileReceiptHash']==o['compileReceiptHash'] and out['exeHash']==c['exeSha256'] and out['sourceHash']==plan['sourceHash']
 archive=R/'factory/native/windows/staged-renderer-byte-archive-v1';ar=j(archive/'receipt.json');dll=archive/'swiftright_render.dll.bin'
 assert dll.stat().st_size==ar['bytes']==11885056 and h(dll)==ar['localSHA256']==ar['remoteMetadata']['sha256']==plan['rendererSha256']
 assert ar['scpExit']==0 and ar['executed'] is False and ar['stagedWrites']==0
 for name in ['Stdout','Stderr']:assert h(archive/('metadata.'+name.lower()+'.bin'))==ar['metadata'+name+'Sha256']
 return {'status':'v5-single-stack-observational-clear','ownedClose':'Exact owned PID/HWND WM_CLOSE receipt bound to retained exit/raw proof','rendererActualArchiveHash':h(dll),'verifiedTransferredFiles':len(t['files']),'nativeObservations':1,'rawFileClosure':len(o['files']),'actualExeByteJoin':c['exeSha256'],'compileReceiptByteJoin':h(run/'observation.json'),'visualRead':'800x600 PrintWindow shows blue rectangle/red circle/+; matches actual host geometry & UIA +','scope':'Source-bound successful observational capture; occluded background qualification & native parity remain held','nativeRunsByReviewer':0,'producerEdits':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
