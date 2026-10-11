"""Read-only actual seeded observation archive joins. No process/native launch."""
from pathlib import Path
import json,hashlib,argparse,re,struct
REPO=Path(__file__).resolve().parents[6]
LANE=REPO/'factory/native/windows/round1-seeded-native-v2'
HOSTS=REPO/'factory/native/windows/round1-seeded-hosts-v1'
refs={}
def raw(p):
 b=p.read_bytes();refs[str(p.relative_to(REPO))]={'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)};return b
def sha(p):return hashlib.sha256(raw(p)).hexdigest()
def load(p):return json.loads(raw(p).decode('utf-8-sig'))
def check(v,msg):
 if not v:raise ValueError(msg)
def scoped(d):
 check(d['nativeParity']=='hold' and d['frozenTupleBound'] is False and d['closureBinding'] is None,'scope promotion')
def review(root):
 batch=load(root/'batch.json');label=batch['case'];count=batch['requested'];check(type(count)is int and count in (1,20),'count')
 check(batch['attempted']==count and batch['retry'] is False and not batch['error'],'batch outcome');scoped(batch)
 contract=load(LANE/'contract.json');check(sha(LANE/'contract.json')==batch['contractHash'],'contract')
 route=next(r for r in contract['hosts'] if r['label']==label)
 package=HOSTS/label/'package';compile_root=HOSTS/label/'build-actual-v2-r1';obs=load(compile_root/'observation.json');plan=load(package/'plan.json')
 check(sha(package/'plan.json')==route['planHash']==obs['planSha256'],'plan')
 check(sha(compile_root/'observation.json')==batch['compileReceiptHash'],'compile receipt')
 check(obs['exitCode']==0 and obs['timedOut'] is False and obs['ownedExited'] is True and obs['streamDrainComplete'] is True,'compile result')
 exe=raw(compile_root/'FactoryProbe.exe');exe_hash=hashlib.sha256(exe).hexdigest();check(exe_hash==obs['exeSha256']==batch['exeHash'],'actual exe')
 pe=struct.unpack_from('<I',exe,0x3c)[0];check(struct.unpack_from('<H',exe,pe+24+68)[0]==2,'GUI PE')
 proof=load(LANE/'proof/source-join.json');check(sha(LANE/'proof/source-join.json')=='9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3','Mac proof')
 mac=next(r for r in proof['cases'] if r['block']==label);check(mac['case']==plan['case'] and mac['witnessHash']==plan['sourceHash'],'Mac source/case')
 check(mac['planHash']=='sha256:'+route['planHash'] and len(mac['runs'])==20,'Mac20 source join')
 directories={p.name for p in (root/'replays').iterdir() if p.is_dir()};check(directories=={f'run-{i:03}' for i in range(1,count+1)},'fresh namespace')
 check(len(batch['rows'])==count and {r['index'] for r in batch['rows']}==set(range(1,count+1)),'batch rows')
 results=[]
 for br in batch['rows']:
  run=root/'replays'/br['run'];native=run/'native-01';receipt=load(run/'native-observation.json');dispatch=load(run/'dispatch.json');outcome=load(native/'capture-outcome.json');owned=load(native/'owned-process.json');launch=load(native/'launch-observation.json');close=load(native/'owned-close.json');pixels=load(native/'native.pixels.json');uia=load(native/'native.uia.json')
  check(sha(run/'dispatch.json')==br['dispatchHash'],'dispatch hash');scoped(dispatch);scoped(receipt)
  check(dispatch['lockAcquired'] is True and dispatch['lockReleased'] is True and dispatch['lockRetainedForUnconfirmedOwnedExit'] is False and not dispatch['cleanupErrors'] and not dispatch['error'],'lock result')
  check(outcome['lockOwner']==dispatch['owner'],'owner join')
  check(receipt['hostValid'] is True and receipt['exitCode']==0 and receipt['probeForegroundAtCapture'] is False,'capture result')
  check(receipt['case']==plan['case'] and receipt['sourceHash']==plan['sourceHash'] and receipt['compileReceiptHash']==batch['compileReceiptHash'] and receipt['exeSha256']==exe_hash,'native lineage')
  check(receipt['rendererSha256']==plan['rendererSha256'] and receipt['runtimeSourceCommit']==plan['runtimeSourceCommit'] and receipt['runtimeSourceTreeHash']==plan['runtimeSourceTreeHash'],'runtime/renderer')
  check(sha(run/'plan.json')==route['planHash'] and sha(run/'observation.json')==batch['compileReceiptHash'],'copied plan/compile')
  for binding in plan['sourceBindings']:
   p=package/binding['path'];check('sha256:'+sha(p)==binding['sha256'],'source binding')
   if binding['path']=='Package.swift' or binding['path'].startswith('Sources/'):
    check(raw(run/binding['path'])==raw(p),'copied consumed source')
  check(raw(run/'Sources/FactoryProbe/Witness.swift')==raw(package/'Sources/FactoryProbe/Witness.swift'),'Witness')
  check(owned==outcome['ownedIdentity'] and owned['path']==obs['exePath'] and type(owned['pid'])is int,'owned identity')
  check(close['pid']==pixels['pid']==owned['pid'] and close['hwnd']==pixels['hwnd']==launch['ownedWindow'],'owned HWND/PID')
  check(close['posted'] is True and close['message']==16 and close['activationRequested'] is False,'WM_CLOSE')
  check(outcome['cleanup']['confirmedOwnedExit'] is True and not outcome['cleanup']['error'] and not outcome['primaryError'] and not outcome['streamErrors'],'cleanup/drain')
  check(outcome['exeHash']==exe_hash and outcome['compileReceiptHash']==batch['compileReceiptHash'] and outcome['macSourceProofHash']=='9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3','outcome provenance')
  for f in receipt['files']:check(sha(native/f['path'])==f['sha256'],'raw receipt file')
  check(sha(native/'host.stdout.txt')==outcome['stdoutSha256'] and sha(native/'host.stderr.txt')==outcome['stderrSha256'],'sealed streams')
  stdout=raw(native/'host.stdout.txt').decode('utf-8-sig');check('FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' in stdout and 'FACTORY_COMMIT version=' in stdout,'actual host guard/commit')
  ready=re.search(r'FACTORY_RENDERER_READY scale=([\d.]+) width=(\d+) height=(\d+) hwnd=(\d+) pid=(\d+) thread=(\d+) dpi=(\d+) metricsSource=owned-client-rect',stdout);check(ready is not None,'ready')
  check(int(ready[2])==pixels['width'] and int(ready[3])==pixels['height'] and int(ready[4])==pixels['hwnd'] and int(ready[5])==owned['pid'] and int(ready[7])==pixels['dpi'],'ready actual metrics')
  check(launch['createNoWindow'] is True and receipt['activationVeto']=='thread-cbt' and receipt['backgroundPlacementRequested'] is True,'background guard observations')
  for sample in pixels['samples']:
   if 'path' in sample:check(sha(native/sample['path'])==sample['sha256'],'pixel bytes')
  check(pixels['printWindowFlags']==3 and pixels['controlledOcclusionQualification'] is False and pixels['providerReadbackExport'] is False,'pixel scope')
  results.append({'run':br['index'],'pid':owned['pid'],'hwnd':pixels['hwnd'],'clientPixels':[pixels['width'],pixels['height']],'dpi':pixels['dpi'],'UIAChildren':len(uia['children']),'WM_CLOSE':True,'confirmedExit':True,'lockReleased':True,'foregroundBefore':launch['foregroundBefore'],'foregroundAfter':launch['foregroundAfter'],'globalForegroundUnchangedProven':False,'PWRepeatStable':pixels['printWindowRepeatStable'],'screenRepeatStable':pixels['screenRepeatStable']})
 return {'decision':'CLEAR-ACTUAL-OBSERVATIONAL-JOINS','case':plan['case'],'count':count,'runs':results,'MacRawStatuses':[r['rawStatus'] for r in mac['runs']],'compilerMacOrigin':'missing OS process receipt','semanticQualification':False,'nativeParity':'hold','files':refs}
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--root',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();check(not a.output.exists(),'fresh report');a.output.write_text(json.dumps(review(a.root.resolve()),indent=2)+'\n')
