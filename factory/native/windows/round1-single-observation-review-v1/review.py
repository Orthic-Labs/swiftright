import pathlib,json,hashlib,struct
ROOT=pathlib.Path(__file__).resolve().parents[4]
OUT=pathlib.Path(__file__).resolve().parent
refs={}
def h(p):
 b=p.read_bytes(); refs[str(p.relative_to(ROOT))]={'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b)};return refs[str(p.relative_to(ROOT))]['sha256']
def load(p):h(p);return json.loads(p.read_text(encoding='utf-8-sig'))
def chk(p,w):assert h(p)==w.removeprefix('sha256:'),(str(p),w,h(p))
BASE=ROOT/'factory/native/windows'
runtime=BASE/'module-origin-37429120-20261011/runtime'
bridge=BASE/'first-capture-corrections-v1/staged-bridge-inputs-r09'
compiler=ROOT/'factory/runtime-additions/taskid-windows-direct-scp-v1/results/swift.exe'
rows=[]
for ver,case,short,build in [(3,'custom-layout','custom','round1-stack-layout-hosts-v1/build-actual-r1/custom-layout'),(3,'padding-frame','padding','round1-next-hosts-v1/padding-frame/build-actual-v2-r1'),(3,'preference-key','preference','round1-next-hosts-v1/preference-key/build-actual-v2-r1'),(4,'scroll','scroll','round1-scroll-build-v4/build-actual-r1')]:
 base=BASE/f'round1-native-v{ver}';r=base/f'single-{case}-r1/replays/run-001';n=r/'native-01';b=BASE/build
 scm=load(base/f'root-single-{short}-output-scp.json');assert scm['scpExit']==0
 for p,w in scm['files'].items():chk(ROOT/p,w)
 plan=load(r/'plan.json');c=load(r/'config.json');co=load(r/'observation.json');no=load(r/'native-observation.json');dis=load(r/'dispatch.json');out=load(n/'capture-outcome.json');pix=load(n/'native.pixels.json');uia=load(n/'native.uia.json');launch=load(n/'launch-observation.json');owned=load(n/'owned-process.json')
 chk(r/'observation.json',c['compileReceiptHash']);chk(r/'plan.json',co['planSha256']);chk(b/'observation.json',c['compileReceiptHash'])
 for f in co['files']:chk(b/f['path'],f['sha256'])
 chk(b/'FactoryProbe.exe',c['exeHash']);assert co['exeSha256']==c['exeHash']==no['exeSha256']
 binary=(b/'FactoryProbe.exe').read_bytes();pe=struct.unpack_from('<I',binary,60)[0];assert struct.unpack_from('<H',binary,pe+24+68)[0]==2
 assert type(co['exitCode']) is int and co['exitCode']==0 and co['timedOut'] is False and co['ownedExited'] is True
 assert co['cwd']==c['package'] and co['exePath']==owned['path'] and c['runRoot'].endswith(f'single-{case}-r1\\replays\\run-001')
 assert 'build --package-path' in co['argv'] and '-c release' in co['argv']
 package=ROOT/'factory/native/windows'/pathlib.PureWindowsPath(c['package']).relative_to('D:/Claude/swiftright/factory/native/windows')
 for f in plan['sourceBindings']:
  chk(package/f['path'],f['sha256'])
  if (r/f['path']).exists():chk(r/f['path'],f['sha256'])
 chk(r/'Sources/FactoryProbe/Witness.swift',plan['sourceHash']);assert plan['sourceHash']==no['sourceHash']==co['sourceHash']
 assert plan['case']==no['case'] and plan['manifestHash']==no['manifestHash']
 manifest=load(package/'witness.manifest.json');assert manifest['case']==plan['case'] if 'case' in manifest else True
 chk(r/'runtime-source-tree.json',plan['runtimeSourceTreeHash']);chk(r/'runtime-source-receipt.json',plan['runtimeSourceReceiptHash'])
 rt=load(r/'runtime-source-receipt.json')
 for f in rt['completeSnapshotBindings']:chk(runtime/f['path'],f['sha256'])
 chk(bridge/'receipt.json',plan['bridgeInputSnapshotReceiptHash'])
 for f in plan['bridgeBindings']:chk(bridge/f['path'],f['sha256']);assert (bridge/f['path']).stat().st_size==f['bytes']
 chk(compiler,plan['compilerHash']);assert no['runtimeSourceCommit']==plan['runtimeSourceCommit']==co['runtimeSourceCommit'] and no['runtimeSourceTreeHash']==plan['runtimeSourceTreeHash']==co['runtimeSourceTreeHash']
 assert c['owner']==dis['owner'] and dis['lockAcquired'] is True and dis['lockReleased'] is True and dis['lockRetainedForUnconfirmedOwnedExit'] is False and not dis['cleanupErrors'] and not dis['error']
 assert load(r/'task-result.json')['status']=='captured-single-observational-uia-printwindow' and load(r/'scheduled-task-receipt.json')['LastTaskResult']==0
 assert no['exitCode']==0 and no['hostValid'] is True and no['probeForegroundAtCapture'] is False and no['nativeParity']=='hold' and no['frozenTupleBound'] is False
 assert out['cleanup']['confirmedOwnedExit'] is True and out['cleanup']['killAttempted'] is False and out['cleanup']['status']=='already-exited' and not out['streamErrors'] and not out['primaryError']
 for f in no['files']:chk(n/f['path'],f['sha256'])
 for stream in ['stdout','stderr']:chk(n/f'host.{stream}.txt',out[f'{stream}Sha256'])
 assert pix['pid']==owned['pid'] and pix['hwnd']==launch['ownedWindow'] and pix['width']==800 and pix['height']==600 and pix['printWindowFlags']==3 and pix['controlledOcclusionQualification'] is False
 for sample in pix['samples']:
  if 'path' in sample:chk(n/sample['path'],sample['sha256'])
 assert pix['printWindowRepeatStable'] is True and pix['screenRepeatStable'] is True and pix['methodsEqual'] is False
 stdout=(n/'host.stdout.txt').read_text();assert f"hwnd={pix['hwnd']} pid={owned['pid']}" in stdout and 'FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' in stdout
 assert 'FACTORY_COMMIT' in stdout and 'FACTORY_RENDER_ERROR' not in stdout and 'FACTORY_STARTUP_ERROR' not in stdout
 for script in ['pixels-background.ps1','host-inputs.ps1']:h(r/script)
 for script in ['capture-repeat.ps1','repeat-task.ps1','run-repeat.ps1','cleanup.ps1','stream-seal.ps1']:h(base/script)
 rows.append({'case':case,'status':'cleared-single-source-bound-observation','compileReceipt':refs[str((r/'observation.json').relative_to(ROOT))],'nativeReceipt':refs[str((r/'native-observation.json').relative_to(ROOT))],'caseIdentity':plan['case'],'sourceSha256':plan['sourceHash'],'exeSha256':c['exeHash'],'compileExit':0,'hostExit':0,'naturalExit':True,'lockReleased':True,'uiaChildren':[x['name'] for x in uia['children']],'printWindowSha256':h(n/'native.printwindow.png'),'printWindowRepeatedBytesEqual':True,'screenRepeatedBytesEqual':True,'screenDiffersFromPrintWindow':True,'probeForegroundAtCapturedSample':False,'foregroundBefore':launch['foregroundBefore'],'foregroundAfter':launch['foregroundAfter'],'window':launch['ownedWindow'],'rendererSha256Receipt':plan['rendererSha256'],'rendererArchiveByteVerified':False,'scope':['one host run','two pixel reads within same run','sampled background guards','source-bound compile/executable','runtime374 source','readonly r09 bridge snapshot'],'notQualified':['parity','repeated-run reproducibility','controlled occlusion','provider pixel readback','continuous foreground state','scroll interaction','Mac primary comparison']})
report={'schema':'independent-round1-single-observation-review-v1','status':'four-bounded-single-observations-cleared','rows':rows,'directRendererByteCheck':'renderer DLL absent from local factory archive; captured harness hashes before & after', 'nonForegroundClaim':'owned-window/process sample checks only; foregroundAfter=0 does not establish preservation of previous foreground window; no continuous-state claim', 'harnessProvenance':'current repository capture/coordinator scripts reviewed & hash referenced; native output receipts bind executed result, no independent recorded per-process loaded-script measurement' ,'pixelVisualInspection':{'custom-layout':'red30x25px tile at25,28','padding-frame':'Box text','preference-key':'0/1/2 text','scroll':'Row0/Row1 painted; UIA lists Row0–Row3'},'inputs':list(sorted(refs.values(),key=lambda r:r['path']))}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'rows':len(rows),'inputFiles':len(refs),'reportSha256':hashlib.sha256((OUT/'report.json').read_bytes()).hexdigest()}))
