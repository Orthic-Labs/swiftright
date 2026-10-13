"""Typed actual capture normalization with explicit prospective identity joins."""
from __future__ import annotations
import importlib.util,re
from pathlib import Path,PurePosixPath
from datetime import datetime,timezone
_spec=importlib.util.spec_from_file_location('settled_v2_readers',Path(__file__).with_name('readers.py'))
r=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(r)

def ticks(value):
 if not isinstance(value,str):raise ValueError('measured UTC instant required')
 m=re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(Z|[+-]\d\d:\d\d)',value)
 if not m:raise ValueError('exact UTC instant syntax')
 dt=datetime.fromisoformat(m[1]+m[3].replace('Z','+00:00')).astimezone(timezone.utc);delta=dt-datetime(1970,1,1,tzinfo=timezone.utc)
 return (delta.days*86400+delta.seconds)*10_000_000+int((m[2] or '').ljust(7,'0'))

def require(value,issue):
 if not value:raise ValueError(issue)

def settled(out):
 pre=out.get('preCleanupExitObservation') or {};states=out.get('rawStreams',[])
 return out.get('primaryError')=='' and out.get('streamErrors')==[] and r.integer(pre.get('kernelWaitResult')) and pre['kernelWaitResult']==0 and r.kernel(out.get('cleanup') or {},True) and len(states)==2 and {s.get('name') for s in states}=={'stdout','stderr'} and all(r.stream(s) for s in states)

def natural_worker(out):
 states=out.get('rawStreams',[])
 return out.get('kind')=='factory-uia-snapshot-worker-exit-v1' and out.get('status')=='completed-natural-uiasnapshot' and out.get('primaryError')=='' and out.get('timedOut') is False and r.integer(out.get('exitCode')) and out['exitCode']==0 and r.integer(out.get('preCleanupKernelWaitResult')) and out['preCleanupKernelWaitResult']==0 and r.kernel(out.get('cleanup') or {},True) and out.get('streamErrors')==[] and len(states)==2 and {s.get('name') for s in states}=={'stdout','stderr'} and all(r.stream(s) for s in states)

def measured_identity(measurement,allocated,owned,exe_hash,issued_hash,run):
 require(measurement.get('kind')=='factory-measured-capture-identity-v1' and measurement.get('issuedMetadataHash')==issued_hash[7:] and measurement.get('run')==run and measurement.get('captureID')==allocated['captureID'] and measurement.get('imageID')==allocated['imageID'],'issued/measurement identity join')
 host=measurement.get('measuredHostIdentity');clock=measurement.get('measuredClockIdentity')
 require(isinstance(host,dict) and isinstance(clock,dict),'planned-identities-are-not-measured-host-clock')
 require(host.get('id')==allocated['plannedHostIdentity'] and host.get('hash')==exe_hash and all(host.get(k)==owned.get(k) for k in ('pid','path','startedAt')),'measured host/owned executable join')
 require(clock.get('clockId')==allocated['plannedClockIdentity'] and clock.get('clockKind')=='process-local-stopwatch' and r.integer(clock.get('frequency')) and clock['frequency']>0 and r.integer(clock.get('processID')) and clock['processID']>0 and r.integer(clock.get('ticks')) and clock['ticks']>=0 and clock.get('crossProcessQualified') is False,'measured process-local receipt clock required')
 ticks(clock.get('utc'));return host,clock

def final_worker(cert,terminal,original,raw_hashes,exe_hash,contract_hash,config_hash,script_hash):
 start=cert.get('start') or {};sample=cert.get('sample') or {};identity=original.get('ownedIdentity') or {}
 require(cert.get('kind')=='factory-uia-final-exit-certificate-v1' and cert.get('scope')=='owner-release-only' and cert.get('qualification')=='failed-or-successful-snapshot-only','worker release-only certificate kind/scope')
 require(all(start.get(k)==identity.get(k) for k in ('pid','path','startedAt','retainedHandle')) and all(r.integer(sample.get(k)) for k in ('retainedHandle','handlePid','kernelBefore','kernelAfter','exitCode')) and sample['retainedHandle']==start['retainedHandle'] and sample['handlePid']==start['pid'] and sample['kernelBefore']==sample['kernelAfter']==0 and 0<=sample['exitCode']<=4294967295 and sample['exitCode']!=259 and r.integer(start.get('pid')) and start['pid']>0 and r.integer(start.get('retainedHandle')) and start['retainedHandle']>0 and sample.get('getExitCodeSucceeded') is True and sample.get('errors')==[] and sample.get('phase')=='raw-closure-final' and r.integer(sample.get('waitMilliseconds')) and sample['waitMilliseconds']==0,'original worker final retained handle sample')
 require(start.get('workerExeHash')==exe_hash[7:] and start.get('sourceContractHash')==contract_hash[7:] and start.get('configHash')==config_hash[7:] and start.get('workerScriptHash')==script_hash[7:],'honest worker executable/source/config identity')
 states=cert.get('rawStreams',[]);require(len(states)==2 and {x.get('name') for x in states}=={'stdout','stderr'} and all(r.stream(x) and x.get('sha256')==raw_hashes.get(x['name'],'')[7:] for x in states),'worker final raw bytes/closure join')
 require(terminal.get('kind')=='factory-uia-terminal-worker-v1' and terminal.get('terminalResultConfirmed') is True and terminal.get('start')==start,'worker terminal/start join')
 return True

MAC_FRESH20_BINARY_HASH='sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777'
MAC_FRESH20_ACCEPTANCE_HASH='sha256:c12eaec44a65627e6f546925664482736bfede7665ab593024c5fcd401998245'

def validate_candidate_wrapper(tuple_document,candidate,plan,compile_record,metadata=None,phase=None,action=None):
 """Production admission validator; action is reached only after every source join passes."""
 try:
  from jsonschema import Draft202012Validator
  common=r.parse((Path(__file__).parent/'dependencies'/'common.schema.json').read_bytes())
  tuple_schema={'$defs':common['$defs'],'$ref':'#/$defs/tuple'}
  errors=sorted(Draft202012Validator(tuple_schema).iter_errors(tuple_document.get('tuple')),key=lambda e:str(e.path))
  require(not errors,'candidate tuple common.schema:'+('; '.join(e.message for e in errors)))
 except ImportError as exc: raise ValueError('canonical-schema-engine-unavailable:'+str(exc)) from exc
 require(tuple_document.get('kind')=='factory-source-bound-candidate-canonical-tuple-v1' and tuple_document.get('version')==1 and tuple_document.get('frozenTupleBound') is False,'candidate tuple wrapper schema')
 t=tuple_document.get('tuple') or {}; c=tuple_document.get('case') or {}; p=plan.get('case') or {}
 require(c==p and t.get('id')==tuple_document.get('candidateID') and re.fullmatch(r'sr1-source-bound-r11-20261011',str(t.get('id')) or ''),'candidate tuple identity/case')
 require(t.get('runtimeCommit')==plan.get('runtimeSourceCommit') and t.get('rendererHash')=='sha256:'+plan.get('rendererSha256') and t.get('hostHashes',{}).get('windows')=='sha256:'+compile_record.get('exeSha256'),'candidate tuple runtime/renderer/windows join')
 require(t.get('hostHashes',{}).get('macos')==MAC_FRESH20_BINARY_HASH and t.get('acceptanceConfigHash')==MAC_FRESH20_ACCEPTANCE_HASH,'candidate tuple actual Mac20 envelope join')
 require(isinstance(tuple_document.get('sourceInputs'),dict) and len(tuple_document['sourceInputs'])>=3,'candidate tuple source inputs')
 for key,ref in tuple_document['sourceInputs'].items():
  require(isinstance(ref,dict) and re.fullmatch(r'sha256:[0-9a-f]{64}',str(ref.get('sha256'))) and isinstance(ref.get('path'),str) and isinstance(ref.get('bytes'),int) and ref['bytes']>=0,'candidate source ref:'+key)
 require(candidate.get('kind')=='factory-source-bound-candidate-binding-v1' and candidate.get('version')==1 and candidate.get('frozenTupleBound') is False,'candidate binding schema')
 require(candidate.get('canonicalTupleRef',{}).get('sha256')==tuple_document.get('_rawSha256'),'candidate canonical tuple ref join')
 require(candidate.get('runtime',{}).get('sourceCommit')==plan.get('runtimeSourceCommit') and candidate.get('renderer',{}).get('sha256')=='sha256:'+plan.get('rendererSha256'),'candidate binding runtime/renderer join')
 if metadata is not None:
  require(metadata.get('kind')=='factory-prelaunch-capture-metadata-v2' and metadata.get('version')==2 and metadata.get('expectedCount') in (1,20) and metadata.get('frozenTupleBound') is False and metadata.get('historicalTemplateTupleClosed') is False,'candidate metadata admission')
  require((metadata.get('candidateTuple') or {}).get('sha256')==tuple_document.get('_rawSha256'),'candidate metadata tuple join')
 if phase is not None: require(phase.get('phase')=='close-pending' and phase.get('nativeActions')==0,'candidate phase admission')
 if action is not None: action()
 return True

def validate_capture(capture):
 # Uses frozen local schemas; dependency absence is explicit hold, never implicit validation.
 try:
  from jsonschema import Draft202012Validator,FormatChecker
  from referencing import Registry,Resource
 except ImportError as exc:raise ValueError('canonical-schema-engine-unavailable:'+str(exc)) from exc
 schemas=[r.parse((Path(__file__).parent/'dependencies'/name).read_bytes()) for name in ('capture.schema.json','common.schema.json')]
 registry=Registry().with_resources([(x['$id'],Resource.from_contents(x)) for x in schemas])
 errors=sorted(Draft202012Validator(schemas[0],registry=registry,format_checker=FormatChecker()).iter_errors(capture),key=lambda e:str(e.path))
 require(not errors,'canonical-capture-schema:'+('; '.join(e.message for e in errors)))
 r._canonical.dump_bytes(capture)
 return True

# Exact producer bytes, not a qualification or review claim. Unknown profiles fail closed.
SUPPORTED_PROFILES={'sha256:fc9e56f668ecb2a3fa67a6b85a01920a72394cda5d5cc3dcdfb8daffc0f36969':{'capturePlanHash':'sha256:1ee850fb370ba85c20c0ccd8b5e4930c9c3b2db39a613d3b53f712f74d970880'}}

def normalize(inputs,read_bytes):
 issues=[];consumed={};captures=[];result={'kind':'settled-typed-capture-normalization-v2','captures':captures,'diagnosticChannels':[],'issues':issues,'consumed':consumed,'qualified':False,'nativeParity':'hold','typedStatus':'held'}
 def read(ref,label):
  require(isinstance(ref,dict) and isinstance(ref.get('path'),str) and re.fullmatch(r'sha256:[0-9a-f]{64}',str(ref.get('sha256'))),'missing-ref:'+label)
  p=PurePosixPath(ref['path']);require(not p.is_absolute() and '..' not in p.parts and str(p)==ref['path'] and '\\' not in ref['path'] and ':' not in ref['path'],'unsafe-ref:'+label)
  raw=read_bytes(dict(ref));require(type(raw) is bytes and r.digest(raw)==ref['sha256'] and ('bytes' not in ref or (r.integer(ref['bytes']) and len(raw)==ref['bytes'])),'raw-byte-join:'+label);consumed[label]=ref;return raw
 def load(ref,label):return r.parse(read(ref,label))
 def get(role):return load(inputs.get('roles',{}).get(role),role)
 try:
  issued=get('issuedMetadata');profile=get('producerProfile');capture_plan=get('capturePlan');plan=get('plan');compile=get('compile');candidate=get('candidateBinding');tuple_document=get('tuple');tuple_value=tuple_document.get('tuple');case=get('case');manifest=get('manifest')
  require(issued.get('kind')=='factory-prelaunch-capture-metadata-v2' and issued.get('version')==2 and issued.get('expectedCount') in (1,20) and r.integer(issued['expectedCount']) and issued.get('frozenTupleBound') is False and issued.get('historicalTemplateTupleClosed') is False,'prospective source-owned metadata format')
  exe=read(inputs['roles'].get('exe'),'exe');renderer=read(inputs['roles'].get('renderer'),'renderer')
  coordinator=get('coordinator')
  require(coordinator.get('lockAcquired') is True and coordinator.get('lockReleased') is True and coordinator.get('wholeBatchExitConfirmed') is True and coordinator.get('terminalResultConfirmed') is True and coordinator.get('error')=='' and coordinator.get('interactiveError')=='' and coordinator.get('cleanupErrors')==[] and coordinator.get('runRoot')==issued.get('runRoot') and r.integer(coordinator.get('count')) and coordinator.get('count')==issued.get('expectedCount'),'complete coordinator/all-owned release proof')
  count=issued['expectedCount'];require(len(inputs.get('runs',[]))==count and len(issued.get('captures',[]))==count and [c.get('run') for c in issued['captures']]==list(range(1,count+1)),'complete issued run membership')
  require(all(isinstance(c.get(k),str) and bool(c[k]) for c in issued['captures'] for k in ('captureID','imageID')) and len({c['captureID'] for c in issued['captures']})==count and len({c['imageID'] for c in issued['captures']})==count,'unique preissued capture/image membership')
  profile_hash=consumed['producerProfile']['sha256'];require(profile_hash in SUPPORTED_PROFILES,'unknown-producer-profile')
  require(consumed['capturePlan']['sha256']==SUPPORTED_PROFILES[profile_hash]['capturePlanHash'],'exact producer capture plan bytes')
  for b in profile['files']:require(read((inputs.get('producerSource') or {}).get(b['path']),'producer:'+b['path']) and consumed['producer:'+b['path']]['sha256']==b.get('sha256',b.get('hash')),'producer source profile join')
  require(capture_plan.get('sourcePlanSha256')==consumed['plan']['sha256'] and capture_plan.get('compiledPlanSha256')==consumed['plan']['sha256'] and capture_plan.get('renderer',{}).get('sha256')=='sha256:'+plan['rendererSha256'],'exact admitted capture/source plan/renderer profile')
  tuple_document['_rawSha256']=consumed['tuple']['sha256']
  validate_candidate_wrapper(tuple_document,candidate,plan,compile,metadata=issued)
  require(tuple_document.get('kind')=='factory-source-bound-candidate-canonical-tuple-v1' and tuple_document.get('frozenTupleBound') is False and tuple_document.get('case')==plan['case'] and isinstance(tuple_value,dict),'source-bound candidate tuple wrapper/case join')
  require((candidate.get('canonicalTupleRef') or {}).get('sha256')==consumed['tuple']['sha256'],'candidate canonical tuple raw ref join')
  require(tuple_value.get('runtimeCommit')==plan['runtimeSourceCommit'] and tuple_value.get('hostHashes',{}).get('windows')=='sha256:'+compile['exeSha256'],'candidate tuple runtime/host actual source join')
  tuple_sources=tuple_document.get('sourceInputs') or {};require('canonicalInputs' in tuple_sources,'candidate tuple canonical source inputs required')
  for key,ref in tuple_sources.items():read(ref,'tupleSource:'+key)
  require(consumed['tupleSource:canonicalInputs']['sha256']==(candidate.get('canonicalInputs') or {}).get('sha256'),'candidate canonical input bytes join')
  for issued_role,role in [('plan','plan'),('compile','compile'),('exe','exe'),('renderer','renderer'),('recipe','manifest'),('sourceBoundCandidateTuple','candidateBinding')]:
   binding=issued.get(issued_role) or {};require(binding.get('sha256')==consumed[role]['sha256'] and binding.get('path')==(inputs.get('metadataRecordPaths') or {}).get(role),'issued actual role/source path join:'+role)
  require(issued['case']==plan['case']==manifest['case'] and r._canonical.sha256(case)==plan['case']['hash'] and case['id']==plan['case']['id'],'actual historical case bytes join')
  require(issued['sourceHash']==plan['sourceHash']==manifest['sourceHash'] and consumed['manifest']['sha256']==plan['manifestHash'],'source manifest join')
  for b in plan['sourceBindings']:require(r.digest(read((inputs.get('source') or {}).get(b['path']),'source:'+b['path']))==b['sha256'],'actual host source join')
  require(consumed['plan']['sha256']=='sha256:'+compile['planSha256'] and compile['sourceHash']==plan['sourceHash'] and r.integer(compile['exitCode']) and compile['exitCode']==0 and compile['timedOut'] is False and compile['streamDrainComplete'] is True,'actual compile original plan/source/exit join')
  require(capture_plan.get('actualBuild',{}).get('compileReceiptSha256')==consumed['compile']['sha256'][7:] and capture_plan.get('actualBuild',{}).get('exeSha256')==compile['exeSha256'] and coordinator.get('compileReceiptHash')==consumed['compile']['sha256'][7:] and coordinator.get('exeHash')==compile['exeSha256'] and coordinator.get('serializerControlSha256')==issued.get('serializerControlSha256') and issued.get('hostArguments')==capture_plan.get('hostArguments')==plan.get('hostArguments'),'producer actual build/coordinator/metadata admission join')
  exe=read(inputs['roles'].get('exe'),'exe');renderer=read(inputs['roles'].get('renderer'),'renderer');require(r.digest(exe)=='sha256:'+compile['exeSha256'] and r.digest(renderer)=='sha256:'+compile['rendererSha256']=='sha256:'+plan['rendererSha256']==tuple_value['rendererHash'],'actual exe/renderer/candidate tuple join')
  require(candidate.get('frozenTupleBound') is False and candidate['runtime']['sourceCommit']==plan['runtimeSourceCommit'] and candidate['runtime']['sourceTreeHash']==plan['runtimeSourceTreeHash'] and candidate['renderer']['sha256']==r.digest(renderer),'tuple11/render/runtime374 distinct source binding')
  require(issued.get('producedRuntimeModules')==compile.get('runtimeModules') and bool(compile.get('runtimeModules')),'actual produced runtime module identity')
  for module in compile['runtimeModules']:
   module_bytes=read((inputs.get('runtimeModules') or {}).get(module['archivePath']),'runtimeModule:'+module['archivePath'])
   require(r.digest(module_bytes)=='sha256:'+module['sha256'] and len(module_bytes)==module['bytes'] and module['runtimeSourceCommit']==plan['runtimeSourceCommit'] and module['runtimeSourceTreeHash']==plan['runtimeSourceTreeHash'],'actual produced additive runtime module bytes/source join')
  for i,bindings in enumerate(inputs['runs'],1):
   def raw(k):return read(bindings.get(k),f'run{i}:'+k)
   def doc(k):return r.parse(raw(k))
   allocated=issued['captures'][i-1];out=doc('outcome');owned=doc('owned');obs=doc('observation');pixels=doc('pixels');close=doc('close');worker=doc('workerExit');measurement=doc('measurement');order=doc('snapshotOrder')
   if isinstance(obs,list):
    require(len(obs)==count and [x.get('index') for x in obs]==list(range(1,count+1)),'complete actual observation run membership');obs=obs[i-1]
   require(obs.get('index')==i,'actual observation run index')
   require(obs.get('hostValid') is True and obs.get('probeForegroundAtCapture') is False and obs.get('backgroundPlacementRequested') is True and out.get('lockOwner')==coordinator.get('owner'),'background/owner exact guard receipt')
   renderer_cert=doc('rendererFinal');renderer_terminal=doc('rendererTerminal')
   rs=renderer_cert.get('start') or {};sp=renderer_cert.get('sample') or {}
   require(renderer_cert.get('kind')=='factory-final-exit-certificate-v1' and renderer_cert.get('scope')=='owner-release-only' and all(rs.get(k)==owned.get(k) for k in ('pid','path','startedAt')) and rs.get('lockOwner')==out.get('lockOwner') and rs.get('compileReceiptHash')==consumed['compile']['sha256'][7:] and rs.get('exeHash')==r.digest(exe)[7:],'renderer release-only original source identity')
   require(all(r.integer(sp.get(k)) for k in ('retainedHandle','handlePid','kernelBefore','kernelAfter','exitCode')) and sp.get('retainedHandle')==rs.get('retainedHandle') and sp.get('handlePid')==owned.get('pid') and sp.get('kernelBefore')==sp.get('kernelAfter')==0 and 0<=sp['exitCode']<=4294967295 and sp.get('exitCode')!=259 and r.integer(rs.get('retainedHandle')) and rs['retainedHandle']>0 and sp.get('getExitCodeSucceeded') is True and sp.get('errors')==[],'renderer final original retained-handle signal')
   require(renderer_terminal.get('kind')=='factory-terminal-worker-v1' and renderer_terminal.get('terminalResultConfirmed') is True and renderer_terminal.get('start')==rs and renderer_terminal.get('finalCertificateHash')==consumed[f'run{i}:rendererFinal']['sha256'][7:] and renderer_terminal.get('originalOutcomeHash')==consumed[f'run{i}:outcome']['sha256'][7:],'renderer terminal/original/final byte join')
   require(settled(out),'original-native-deadline-or-raw-failure')
   require(natural_worker(worker),'original-worker-natural-exit-or-raw-failure')
   require(out['ownedIdentity']==owned and owned['path']==compile['exePath'] and ticks(issued['createdAt'])<ticks(owned['startedAt']),'prelaunch-issued metadata/owned start join')
   require(out['compileReceiptHash']==consumed['compile']['sha256'][7:] and out['exeHash']==r.digest(exe)[7:] and out['sourceHash']==plan['sourceHash'] and obs['sourceHash']==plan['sourceHash'] and obs['case']==plan['case'],'original native source/compile join')
   require(close['pid']==pixels['pid']==owned['pid'] and close['hwnd']==pixels['hwnd'] and close['posted'] is True and close['activationRequested'] is False and close['message']==16,'owned pixel/WM_CLOSE join')
   require(worker['target']=={'pid':owned['pid'],'hwnd':pixels['hwnd'],'path':owned['path'],'startedAt':owned['startedAt'],'lockOwner':out['lockOwner']},'worker target scalar ownership join')
   worker_cert=doc('workerFinal');worker_terminal=doc('workerTerminal')
   worker_raw_hashes={name:r.digest(raw('worker'+name.capitalize())) for name in ('stdout','stderr')}
   worker_exe=raw('workerExe');worker_contract=raw('workerContract');worker_config=raw('workerConfig');worker_script=raw('workerScript')
   final_worker(worker_cert,worker_terminal,worker,worker_raw_hashes,r.digest(worker_exe),r.digest(worker_contract),r.digest(worker_config),r.digest(worker_script))
   require(worker_terminal.get('finalCertificateHash')==consumed[f'run{i}:workerFinal']['sha256'][7:] and worker_terminal.get('originalOutcomeHash')==consumed[f'run{i}:workerExit']['sha256'][7:],'worker terminal/original/final byte join')
   wc=r.parse(worker_contract);cfg=r.parse(worker_config)
   require(cfg.get('sourceBindings')==wc.get('sourceBindings') and cfg.get('target')==worker['target'] and cfg.get('outputRoot')==worker_cert['start'].get('workerId') and worker_cert['start'].get('lockOwner')==out['lockOwner'],'worker config/contract/target join')
   for b in wc['sourceBindings']:require(r.digest(read((bindings.get('workerSource') or {}).get(b['path']),f'run{i}:workerSource:'+b['path']))=='sha256:'+b['sha256'],'worker actual source bytes join')
   host,clock=measured_identity(measurement,allocated,owned,r.digest(exe),consumed['issuedMetadata']['sha256'],i)
   uia=raw('uia');stdout=raw('stdout');stderr=raw('stderr');png=raw('printWindow')
   require(r.digest(stdout)[7:]==out['stdoutSha256'] and r.digest(stderr)[7:]==out['stderrSha256'] and r.digest(uia)[7:]==worker['uiaSha256'],'actual scalar/raw bytes join')
   renderer_states=renderer_cert.get('rawStreams',[]);require(len(renderer_states)==2 and {s.get('name') for s in renderer_states}=={'stdout','stderr'} and all(r.stream(s) and s.get('sha256')==r.digest(stdout if s['name']=='stdout' else stderr)[7:] for s in renderer_states),'renderer final raw closure/bytes join')
   for name in ('stdout','stderr'):require(r.digest(raw('worker'+name.capitalize()))[7:]==worker[name+'Sha256'],'actual worker stream bytes join')
   require(order.get('kind')=='factory-isolated-uia-parent-ordering-v1' and order.get('issuedMetadataHash')==consumed['issuedMetadata']['sha256'][7:] and order.get('workerReceiptHash')==consumed[f'run{i}:workerExit']['sha256'][7:] and order.get('workerFinalCertificateHash')==consumed[f'run{i}:workerFinal']['sha256'][7:] and order.get('snapshotHash')==r.digest(uia)[7:],'source-owned isolated worker ordering receipt joins')
   require(order.get('pixelReceiptHash')==consumed[f'run{i}:pixels']['sha256'][7:] and order.get('ownedCloseReceiptHash')==consumed[f'run{i}:close']['sha256'][7:] and order.get('pixelSamples')==pixels.get('samples'),'source-owned pixel/close ordering byte joins')
   require(all(order.get('rendererIdentity',{}).get(k)==owned.get(k) for k in ('pid','path','startedAt')) and order.get('parentProcessID')==clock['processID'] and order.get('frequency')==clock['frequency'] and order.get('clockDomain')=='parent-process-local-stopwatch' and order.get('crossProcessClockQualified') is False,'parent ordering domain/renderer identity join')
   ordering_ticks=[order.get(k) for k in ('workerVerifiedTicks','pixelsStartTicks','pixelsEndTicks','ownedCloseStartTicks','ownedCloseEndTicks')]
   require(all(r.integer(t) and t>=0 for t in ordering_ticks) and ordering_ticks==sorted(ordering_ticks),'natural worker verified before pixels/close in same parent clock domain')
   repeat_png=raw('printWindowRepeat')
   pixel_samples=[x for x in pixels.get('samples',[]) if x.get('method')=='printwindow']
   require(len(pixel_samples)==2 and {x.get('repeat') for x in pixel_samples}=={1,2} and {x.get('sha256') for x in pixel_samples}=={r.digest(png)[7:],r.digest(repeat_png)[7:]} and pixels.get('printWindowFlags')==3,'actual PrintWindow pixel pair join')
   projection=r.channels(r.parse(uia),png,stdout)
   repeat_projection=r.channels(r.parse(uia),repeat_png,stdout)
   require(all(projection['printWindow'][k]==repeat_projection['printWindow'][k] for k in ('widthPx','heightPx','captureScale')),'PrintWindow pair measured dimensions/scale join')
   prov=allocated['provenance'];require(prov['sourceHash']==plan['sourceHash'] and prov['createdAt']==issued['createdAt'] and isinstance(prov['producer'],str) and bool(prov['producer']),'issued provenance source/time producer join')
   capture={'kind':'capture','version':'0.1','id':allocated['captureID'],'provenance':prov,'case':plan['case'],'platform':'windows','tuple':tuple_value,'meta':{'run':i,'host':{'id':host['id'],'hash':host['hash']},'clock':{'clockId':clock['clockId'],'correlationHash':consumed[f'run{i}:measurement']['sha256']},'conditions':{'evidenceClass':'observational-native','frozenTupleBound':False,'nativeParity':'hold','providerPaintAvailable':False,'layoutAvailable':False,'animationClockCorrelated':False,'nativeProviderClockQualified':False,'clockKind':'process-local-stopwatch','issuedMetadataHash':consumed['issuedMetadata']['sha256'],'originalOutcomeHash':consumed[f'run{i}:outcome']['sha256'],'rawUIAHash':r.digest(uia),'sourceBoundCandidateTupleHash':consumed['candidateBinding']['sha256']}},'layout':[],'ax':projection['ax'],'events':[],'anim':[],'images':[dict(id=allocated['imageID'],**projection['printWindow'])],'text':[]}
   validate_capture(capture)
   captures.append(capture)
  result['typedStatus']='normalized-observational';result['issues'].extend(['provider/layout/text/event/animation/native-provider-clock unavailable','F10 origin admission requires independent archived-reader proof'])
 except (ValueError,KeyError,TypeError,IndexError,OSError) as e:
  captures.clear();issues.append(str(e))
  # Reader projections stay diagnostic: no minted identity, provenance, tuple, or eligibility.
  for i,bindings in enumerate(inputs.get('runs',[]),1):
   try:
    uia=read(bindings.get('uia'),f'diagnostic{i}:uia');png=read(bindings.get('printWindow'),f'diagnostic{i}:printWindow');stdout=read(bindings.get('stdout'),f'diagnostic{i}:stdout')
    result['diagnosticChannels'].append({'inputRunOrdinal':i,'qualification':'unqualified-reader-projection','channels':r.channels(r.parse(uia),png,stdout),'rawRefs':{k:bindings.get(k) for k in ('uia','printWindow','stdout')}})
   except (ValueError,KeyError,TypeError,IndexError,OSError) as diagnostic_error:issues.append(f'diagnostic-run{i}:'+str(diagnostic_error))
 return result
