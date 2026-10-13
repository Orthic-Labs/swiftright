#!/usr/bin/env python3
"""Read-only padding single audit. Writes report only inside this independent-review namespace."""
from pathlib import Path
import json,hashlib,struct,datetime
repo=Path('/Volumes/D/claude/swiftright');review=Path(__file__).resolve().parent
lane=repo/'factory/native/windows/round1-seeded-native-v5';root=lane/'single-padding-frame-r1';run=root/'replays/run-001';native=run/'native-01';host=repo/'factory/native/windows/round1-seeded-hosts-v1/padding-frame';package=host/'package';build=host/'build-actual-v2-r1'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
checks=[]
def check(name,condition):
 if not condition:raise AssertionError(name)
 checks.append(name)
def boolean(value,expected):return type(value) is bool and value is expected
def zero(value):return type(value) is int and value==0
batch=load(root/'batch.json');dispatch=load(run/'dispatch.json');outcome=load(native/'capture-outcome.json');plan=load(run/'plan.json');compiled=load(run/'observation.json');record=load(run/'native-observation.json');owned=load(native/'owned-process.json');close=load(native/'owned-close.json');launch=load(native/'launch-observation.json');pixels=load(native/'native.pixels.json');uia=load(native/'native.uia.json');config=load(run/'config.json')
check('exact33 fetched files',len(list(p for p in root.rglob('*') if p.is_file()))==33)
check('single fresh namespace',sorted(p.name for p in (root/'replays').iterdir())==['run-001'] and sorted(p.name for p in run.glob('native-*') if p.is_dir())==['native-01'])
check('batch exactly one completed',batch['status']=='completed-1-observational' and type(batch['requested']) is int and batch['requested']==1 and batch['attempted']==1 and not batch['error'] and boolean(batch['retry'],False))
check('batch dispatch byte join',len(batch['rows'])==1 and batch['rows'][0]['run']=='run-001' and batch['rows'][0]['dispatchHash']==sha(run/'dispatch.json'))
check('frozen v5 source bytes',all(sha(repo/e['path'])==e['sha256'].removeprefix('sha256:') for e in load(lane/'root-stage-manifest.json')['files']))
check('native contract exact hash',sha(lane/'contract.json')==batch['contractHash']=='5285021869f6f21ee0013c434d1171a25830b6161f98b8ddcbed2fca5bc65861')
contract=load(lane/'contract.json');hostRows=[h for h in contract['hosts'] if h['label']=='padding-frame'];check('exact single padding contract row',len(hostRows)==1)
def remoteLocal(remote):
 path=remote.replace('\\','/')
 while '//' in path:path=path.replace('//','/')
 return repo/path.removeprefix('D:/Claude/swiftright/')
check('all consumed driver/helper contract byte pins',all(sha(remoteLocal(b['path']))==b['sha256'] for b in hostRows[0]['bindings']))
check('captured factory helpers byte joins',sha(run/'host-inputs.ps1')==sha(repo/'factory/native/windows/round1-stack-layout-hosts-v1/shared/host-inputs.ps1')=='93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db' and sha(run/'pixels-background.ps1')==sha(repo/'factory/native/windows/pixels-background.ps1')=='7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef')
check('host plan exact byte identity',sha(run/'plan.json')==sha(package/'plan.json')==compiled['planSha256']=='be73260accb728a1a613913be4503fae8414623218d129b7ed38eb2f609c7aaf')
check('all frozen compiler source bindings',all(sha(package/b['path'])==b['sha256'].removeprefix('sha256:') for b in plan['sourceBindings']))
snapshotBindings=[b for b in plan['sourceBindings'] if b['path']=='Package.swift' or b['path'].startswith('Sources/')]
check('captured source membership exact',sorted(['Package.swift']+[str(p.relative_to(run)) for p in (run/'Sources').rglob('*') if p.is_file()])==sorted(b['path'] for b in snapshotBindings))
check('captured source byte identity',all(sha(run/b['path'])==b['sha256'].removeprefix('sha256:') for b in snapshotBindings))
check('witness source exact padding pin',sha(run/'Sources/FactoryProbe/Witness.swift')=='b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b' and outcome['sourceHash']==record['sourceHash']==compiled['sourceHash']==plan['sourceHash'])
check('runtime source receipt/tree byte identity',all(sha(run/name)==sha(package/name)==plan[field].removeprefix('sha256:') for name,field in [('runtime-source-receipt.json','runtimeSourceReceiptHash'),('runtime-source-tree.json','runtimeSourceTreeFileHash')]))
check('compile receipt exact actual archive bytes',sha(run/'observation.json')==sha(build/'observation.json')==batch['compileReceiptHash']==outcome['compileReceiptHash']==record['compileReceiptHash']=='5f19a3bacc50f7b1ee97cfb68d4cefdf48eae04194e22585d3a5527a97fa412d')
check('compile successful owned natural exit',compiled['kind']=='factory-compile-only-owned-handle-v2' and zero(compiled['exitCode']) and boolean(compiled['ownedExited'],True) and boolean(compiled['timedOut'],False) and boolean(compiled['streamDrainComplete'],True) and compiled['cleanupAction']=='natural-exit-no-termination' and compiled['error'] is None and compiled['cleanupError'] is None)
check('compile stdout/stderr archive joins',all(sha(build/f['path'])==f['sha256'] and (build/f['path']).stat().st_size==f['bytes'] for f in compiled['files']))
check('exe exact actual bytes',sha(build/'FactoryProbe.exe')==batch['exeHash']==outcome['exeHash']==record['exeSha256']==compiled['exeSha256']=='6c4508372a43e49b72ff0b4a2a3d71d988c8720e7706ae0fe742d9bfda9f5f5b')
b=(build/'FactoryProbe.exe').read_bytes();pe=struct.unpack_from('<I',b,60)[0]
check('actual executable GUI PE2',b[:2]==b'MZ' and b[pe:pe+4]==b'PE\0\0' and struct.unpack_from('<H',b,pe+24+68)[0]==compiled['exeSubsystem']==2)
check('runtime/compiler pin joins',compiled['runtimeSourceCommit']==record['runtimeSourceCommit']==plan['runtimeSourceCommit']=='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b' and compiled['runtimeSourceTreeHash']==record['runtimeSourceTreeHash']==plan['runtimeSourceTreeHash'] and compiled['compilerHash']==plan['compilerHash']=='1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a')
renderer=repo/'factory/native/windows/staged-renderer-byte-archive-v1/swiftright_render.dll.bin'
check('renderer actual archived bytes pin',sha(renderer)==plan['rendererSha256']==compiled['rendererSha256']==record['rendererSha256']=='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93')
check('case/manifest exact pins',record['case']==plan['case'] and record['case']['id']=='swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258' and record['case']['hash']=='sha256:84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d' and record['manifestHash']==plan['manifestHash']=='sha256:'+sha(package/'witness.manifest.json'))
proof=load(lane/'proof/source-join.json');expected=load(lane/'proof-contract.json')
check('Mac parent proof exact bytes',sha(lane/'proof/source-join.json')==outcome['macSourceProofHash']=='9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3' and sha(lane/'proof-contract.json')=='2a2f4f64da212cb187ff893dcade8c774ef292d7618dc511c455473bb00ec0b1')
for wanted in expected['cases']:
 actual=[c for c in proof['cases'] if c['block']==wanted['block']];check('Mac exact selected contract '+wanted['block'],len(actual)==1 and all(actual[0][k]==wanted[k] for k in ['planHash','witnessHash','adaptedHostHash','binaryHash','case','runs']))
padding=next(c for c in expected['cases'] if c['block']=='padding-frame');check('Mac parent plan/witness/case join',padding['planHash']=='sha256:'+sha(package/'plan.json') and padding['witnessHash']==plan['sourceHash'] and padding['case']==plan['case'])
check('lock acquired/released exact owner',dispatch['status']=='captured-single-observational-uia-printwindow' and boolean(dispatch['lockAcquired'],True) and boolean(dispatch['lockReleased'],True) and boolean(dispatch['lockRetainedForUnconfirmedOwnedExit'],False) and dispatch['owner']==config['owner']==outcome['lockOwner'] and not dispatch['error'] and dispatch['cleanupErrors']==[])
check('owned identity exact capture/compile join',outcome['ownedIdentity']=={k:owned[k] for k in ['pid','path','startedAt']} and owned['path']==compiled['exePath'] and config['compileReceiptHash']==batch['compileReceiptHash'] and config['exeHash']==batch['exeHash'])
check('background noactivation observed',boolean(record['probeForegroundAtCapture'],False) and boolean(record['backgroundPlacementRequested'],True) and record['activationVeto']=='thread-cbt' and boolean(launch['createNoWindow'],True) and launch['foregroundAfter']!=launch['ownedWindow'] and record['foregroundBeforeLaunch']==launch['foregroundBefore'] and record['foregroundAfterWindow']==launch['foregroundAfter'])
capture=(lane/'capture-repeat.ps1').read_text();check('frozen noactivate bottom/window targeted source',all(s in capture for s in ['SetWindowPos($hwnd,[IntPtr]::new(1),0,0,0,0,0x0013)','AutomationElement]::FromHandle($hwnd)','Capture-FactoryPixels $hwnd $p.Id $dir $guard','[DateTime]::UtcNow.AddSeconds(15)']))
check('owned WM_CLOSE target noactivation',close['hwnd']==launch['ownedWindow']==pixels['hwnd'] and close['pid']==owned['pid']==pixels['pid'] and close['message']==16 and close['messageName']=='WM_CLOSE' and boolean(close['posted'],True) and boolean(close['activationRequested'],False))
pre=outcome['preCleanupExitObservation'];cleanup=outcome['cleanup'];check('retained kernel0 before cleanup no primary error',zero(pre['kernelWaitResult']) and boolean(pre['hasExitedObserved'],True) and outcome['primaryError']=='')
check('cleanup already-signaled kernel0 no kill',zero(cleanup['kernelWaitResult']) and boolean(cleanup['confirmedOwnedExit'],True) and boolean(cleanup['kernelExitSignaled'],True) and boolean(cleanup['killAttempted'],False) and cleanup['exitCertification']=='retained-kernel-handle' and cleanup['status']=='already-signaled' and cleanup['error']=='' and outcome['streamErrors']==[])
for scope in [pre,outcome]:
 streams=scope['rawStreams'];check('exact two streams '+('preCleanup' if scope is pre else 'final'),len(streams)==2 and sorted(s['name'] for s in streams)==['stderr','stdout'])
 for s in streams:
  check('terminal sealed closed '+s['name']+(' pre' if scope is pre else ' final'),all(boolean(s[k],True) for k in ['copyCompleted','destinationClosed','sealed','taskIsCompleted']) and all(boolean(s[k],False) for k in ['taskIsFaulted','taskIsCanceled']) and s['taskStatus']==s['closureTaskStatus']=='RanToCompletion' and s['taskException']=='' and s['hashQualification']=='sealed-raw')
  c=s['closure'];check('flush closure bounded success '+s['name']+(' pre' if scope is pre else ' final'),c['deadlineMilliseconds']==5000 and c['flushDisposition']=='requested-terminal-copy' and all(boolean(c[k],True) for k in ['flushCompleted','destinationClosed','completedWithinDeadline']) and boolean(c['deadlineExpired'],False) and c['error']=='')
check('raw bytes qualified sealed joins',outcome['rawHashesQualification']=='sealed-raw' and all(sha(native/('host.'+s+'.txt'))==outcome[s+'Sha256']==outcome['rawHashStates'][s]['sha256'] and outcome['rawHashStates'][s]['qualification']=='sealed-raw' and outcome['rawHashStates'][s]['error']=='' for s in ['stdout','stderr']))
check('exact native capture/raw file membership joins',sorted(f['path'] for f in record['files'])==sorted(p.name for p in native.iterdir() if p.is_file()) and all(sha(native/f['path'])==f['sha256'] for f in record['files']))
check('pixels flag3 targeted method exact',pixels['printWindowFlags']==3 and pixels['printWindowFlagNames']=='PW_CLIENTONLY|PW_RENDERFULLCONTENT' and record['captureMethod']=='UIA+PrintWindow(PW_CLIENTONLY|PW_RENDERFULLCONTENT)+CopyFromScreen')
images=[s for s in pixels['samples'] if 'method' in s];check('four pixel samples repeat hash joins',len(images)==4 and all(sha(native/s['path'])==s['sha256'] for s in images) and boolean(pixels['printWindowRepeatStable'],True) and boolean(pixels['screenRepeatStable'],True))
check('actual PNG dimensions',all((native/s['path']).read_bytes()[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',(native/s['path']).read_bytes()[16:24])==(pixels['width'],pixels['height']) for s in images))
check('target UIA one Box leaf',uia['name']=='Alchemist FactoryProbe' and uia['controlType']=='ControlType.Window' and len(uia['children'])==1 and uia['children'][0]['name']=='Box' and uia['children'][0]['automationId']=='Root/#0/Modified/Modified/Text')
stdout=(native/'host.stdout.txt').read_text();stderr=(native/'host.stderr.txt').read_text();check('host ready valid exit0 no render error',zero(record['exitCode']) and boolean(record['hostValid'],True) and all(s in stdout for s in ['FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto','FACTORY_RENDERER_READY','FACTORY_COMMIT']) and 'FACTORY_RENDER_ERROR' not in stdout and 'FACTORY_STARTUP_ERROR' not in stdout)
check('shutdown postclose drain observed', 'post_close_drains=1 post_close_timeouts=0' in stderr and '[swiftright-render] shutdown' in stderr and '[swiftright-render] memory' in stderr)
check('all qualification holds preserved',all(d.get('nativeParity')=='hold' and boolean(d.get('frozenTupleBound'),False) and d.get('closureBinding') is None for d in [batch,dispatch,record,compiled]) and boolean(record['occlusionQualified'],False) and boolean(pixels['controlledOcclusionQualification'],False) and boolean(pixels['providerReadbackExport'],False))
parseTime=lambda s:datetime.datetime.fromisoformat(s.replace('Z','+00:00'))
delta=(parseTime(pre['at'])-parseTime(close['at'])).total_seconds()
result={'kind':'independent-actual-padding-single-review-v1','status':'CLEAR_SINGLE_OBSERVATIONAL','checked':checks,'checkCount':len(checks),'producerBatchStatus':batch['status'],'pid':owned['pid'],'WM_CLOSE_at':close['at'],'preCleanup_at':pre['at'],'WM_CLOSE_to_preCleanupMilliseconds':round(delta*1000,3),'preCleanupKernelWaitResult':0,'cleanupStatus':'already-signaled','rawHashesQualification':'sealed-raw','stdoutSha256':outcome['stdoutSha256'],'stderrSha256':outcome['stderrSha256'],'rendererArchivedBytesSha256':sha(renderer),'nativeParity':'hold','frozenTupleBound':False,'ABI_SR0_qualificationChanged':False,'prospectiveF10CompileRequest':'held-missing-per-parent-task; no promotion','evidence':[{'path':str(p.relative_to(repo)),'sha256':'sha256:'+sha(p),'bytes':p.stat().st_size} for p in sorted(root.rglob('*')) if p.is_file()]}
(review/'report.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'status':result['status'],'checks':len(checks),'reportSha256':sha(review/'report.json'),'closeToSignalObservationMilliseconds':result['WM_CLOSE_to_preCleanupMilliseconds']}))
