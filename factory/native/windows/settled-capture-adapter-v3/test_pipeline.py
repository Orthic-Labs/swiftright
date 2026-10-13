"""Explicit structural fixture; never represented as actual native evidence."""
import copy,json,unittest
from test_adapter import a,HERE,REPO,load

def fixture():
 store={};roles={};runs={};records={}
 def raw(name,value):
  data=value if type(value) is bytes else json.dumps(value,separators=(',',':')).encode();store[name]=data
  return {'path':name,'sha256':a.r.digest(data),'bytes':len(data)}
 def role(name,value):roles[name]=raw(name+'.json',value);records[name]='fixture-record/'+name;return roles[name]
 def run(name,value):runs[name]=raw('run/'+name,value);return runs[name]
 base=REPO/'factory/native/windows/round1-seeded-native-v5/single-padding-frame-r1/replays/run-001/native-01'
 case={'id':'fixture.case'};caseid={'id':case['id'],'hash':a.r._canonical.sha256(case)}
 sourcehash='sha256:'+'a'*64;renderer=b'fixture renderer';exe=b'fixture exe';hostargs=['--factory-capture-lease-seconds=40']
 role('case',case);role('manifest',{'case':caseid,'sourceHash':sourcehash});role('exe',exe);role('renderer',renderer)
 plan={'case':caseid,'sourceHash':sourcehash,'manifestHash':roles['manifest']['sha256'],'sourceBindings':[],'rendererSha256':a.r.digest(renderer)[7:],'runtimeSourceCommit':'37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b','runtimeSourceTreeHash':'sha256:'+'b'*64,'hostArguments':hostargs};role('plan',plan)
 module={'archivePath':'fixture.module','sha256':a.r.digest(b'module')[7:],'bytes':6,'runtimeSourceCommit':plan['runtimeSourceCommit'],'runtimeSourceTreeHash':plan['runtimeSourceTreeHash']}
 compile={'planSha256':roles['plan']['sha256'][7:],'sourceHash':sourcehash,'exitCode':0,'timedOut':False,'streamDrainComplete':True,'exeSha256':a.r.digest(exe)[7:],'rendererSha256':a.r.digest(renderer)[7:],'exePath':'fixture.exe','runtimeModules':[module]};role('compile',compile)
 canonical=raw('canonical.json',{'kind':'fixture.context'}); context_raw=raw('context.json',{'kind':'fixture.context.raw'}); context_raw2=raw('context2.json',{'kind':'fixture.context.raw2'})
 tup={'id':'sr1-source-bound-r11-20261011','sdk':'fixture.sdk','macosBuild':'fixture.mac','toolchains':{'windows':'fixture.toolchain'},'runtimeCommit':plan['runtimeSourceCommit'],'rendererHash':a.r.digest(renderer),'hostHashes':{'macos':a.MAC_FRESH20_BINARY_HASH,'windows':a.r.digest(exe)},'factoryVersion':'0.1','acceptanceConfigHash':a.MAC_FRESH20_ACCEPTANCE_HASH}
 role('tuple',{'kind':'factory-source-bound-candidate-canonical-tuple-v1','version':1,'candidateID':tup['id'],'case':caseid,'frozenTupleBound':False,'tuple':tup,'sourceInputs':{'canonicalInputs':canonical,'macContext_capture':context_raw,'macContext_verify':context_raw2}})
 tup_ref=roles['tuple']; tup['_rawSha256']=tup_ref['sha256']
 candidate={'kind':'factory-source-bound-candidate-binding-v1','version':1,'canonicalTupleRef':roles['tuple'],'canonicalInputs':canonical,'frozenTupleBound':False,'runtime':{'sourceCommit':plan['runtimeSourceCommit'],'sourceTreeHash':plan['runtimeSourceTreeHash']},'renderer':{'sha256':a.r.digest(renderer)}};role('candidateBinding',candidate)
 cp={'sourcePlanSha256':roles['plan']['sha256'],'compiledPlanSha256':roles['plan']['sha256'],'renderer':{'sha256':a.r.digest(renderer)},'actualBuild':{'compileReceiptSha256':roles['compile']['sha256'][7:],'exeSha256':compile['exeSha256']},'hostArguments':hostargs};role('capturePlan',cp)
 profile={'files':[{'path':'fixture/capture-plan.json','hash':roles['capturePlan']['sha256'],'bytes':roles['capturePlan']['bytes']}]};role('producerProfile',profile)
 allocated={'run':1,'captureID':'fixture.preissued.capture','imageID':'fixture.preissued.image','plannedHostIdentity':'fixture.observed.host','plannedClockIdentity':'fixture.receipt.clock','provenance':{'sourceHash':sourcehash,'createdAt':'2026-10-11T00:00:00Z','producer':'explicit-test-fixture'}}
 issued={'kind':'factory-prelaunch-capture-metadata-v2','version':2,'expectedCount':1,'frozenTupleBound':False,'historicalTemplateTupleClosed':False,'runRoot':'fixture.root','case':caseid,'sourceHash':sourcehash,'createdAt':allocated['provenance']['createdAt'],'captures':[allocated],'producedRuntimeModules':[module],'serializerControlSha256':'d'*64,'hostArguments':hostargs}
 issued['candidateTuple']=roles['tuple']
 for key,name in [('plan','plan'),('compile','compile'),('exe','exe'),('renderer','renderer'),('recipe','manifest'),('sourceBoundCandidateTuple','candidateBinding')]:issued[key]=dict(roles[name],path=records[name])
 role('issuedMetadata',issued)
 coord={'lockAcquired':True,'lockReleased':True,'wholeBatchExitConfirmed':True,'terminalResultConfirmed':True,'error':'','interactiveError':'','cleanupErrors':[],'runRoot':issued['runRoot'],'count':1,'owner':'fixture.owner','compileReceiptHash':roles['compile']['sha256'][7:],'exeHash':compile['exeSha256'],'serializerControlSha256':issued['serializerControlSha256']};role('coordinator',coord)
 owned={'pid':1,'path':compile['exePath'],'startedAt':'2026-10-11T00:00:01Z'};run('owned',owned)
 out=load(base/'capture-outcome.json');out.update(ownedIdentity=owned,lockOwner=coord['owner'],compileReceiptHash=coord['compileReceiptHash'],exeHash=compile['exeSha256'],sourceHash=sourcehash)
 run('outcome',out);run('stdout',(base/'host.stdout.txt').read_bytes());run('stderr',(base/'host.stderr.txt').read_bytes());run('uia',(base/'native.uia.json').read_bytes());run('printWindow',(base/'native.printwindow.png').read_bytes());run('printWindowRepeat',(base/'native.printwindow.repeat.png').read_bytes())
 run('observation',{'index':1,'hostValid':True,'probeForegroundAtCapture':False,'backgroundPlacementRequested':True,'sourceHash':sourcehash,'case':caseid})
 pixels=load(base/'native.pixels.json');pixels['pid']=owned['pid'];run('pixels',pixels)
 close=load(base/'owned-close.json');close['pid']=owned['pid'];run('close',close)
 sample={'retainedHandle':7,'handlePid':1,'kernelBefore':0,'kernelAfter':0,'exitCode':0,'getExitCodeSucceeded':True,'errors':[],'phase':'raw-closure-final','waitMilliseconds':0}
 start=dict(owned,retainedHandle=7,lockOwner=coord['owner'],compileReceiptHash=coord['compileReceiptHash'],exeHash=compile['exeSha256'])
 renderer_streams=copy.deepcopy(out['rawStreams'])
 for row in renderer_streams:row['sha256']=runs[row['name']]['sha256'][7:]
 rc={'kind':'factory-final-exit-certificate-v1','scope':'owner-release-only','start':start,'sample':sample,'rawStreams':renderer_streams};run('rendererFinal',rc)
 run('rendererTerminal',{'kind':'factory-terminal-worker-v1','terminalResultConfirmed':True,'start':start,'finalCertificateHash':runs['rendererFinal']['sha256'][7:],'originalOutcomeHash':runs['outcome']['sha256'][7:]})
 target=dict(owned,hwnd=pixels['hwnd'],lockOwner=coord['owner']);contract={'sourceBindings':[]};config={'sourceBindings':[],'target':target,'outputRoot':'fixture.worker'}
 run('workerContract',contract);run('workerConfig',config);run('workerExe',b'fixture powershell');run('workerScript',b'fixture script');run('workerStdout',b'');run('workerStderr',b'')
 wi={'pid':2,'path':'fixture.ps','startedAt':'2026-10-11T00:00:02Z','retainedHandle':8};ws=dict(wi,workerId='fixture.worker',lockOwner=coord['owner'],workerExeHash=runs['workerExe']['sha256'][7:],sourceContractHash=runs['workerContract']['sha256'][7:],configHash=runs['workerConfig']['sha256'][7:],workerScriptHash=runs['workerScript']['sha256'][7:])
 streams=copy.deepcopy(out['rawStreams'])
 for row in streams:row['sha256']=a.r.digest(b'')[7:]
 worker={'kind':'factory-uia-snapshot-worker-exit-v1','status':'completed-natural-uiasnapshot','primaryError':'','timedOut':False,'exitCode':0,'preCleanupKernelWaitResult':0,'cleanup':out['cleanup'],'streamErrors':[],'rawStreams':streams,'ownedIdentity':wi,'target':target,'uiaSha256':runs['uia']['sha256'][7:],'stdoutSha256':a.r.digest(b'')[7:],'stderrSha256':a.r.digest(b'')[7:]};run('workerExit',worker)
 wc={'kind':'factory-uia-final-exit-certificate-v1','scope':'owner-release-only','qualification':'failed-or-successful-snapshot-only','start':ws,'sample':dict(sample,retainedHandle=8,handlePid=2),'rawStreams':streams};run('workerFinal',wc)
 run('workerTerminal',{'kind':'factory-uia-terminal-worker-v1','terminalResultConfirmed':True,'start':ws,'finalCertificateHash':runs['workerFinal']['sha256'][7:],'originalOutcomeHash':runs['workerExit']['sha256'][7:]})
 measurement={'kind':'factory-measured-capture-identity-v1','issuedMetadataHash':roles['issuedMetadata']['sha256'][7:],'run':1,'captureID':allocated['captureID'],'imageID':allocated['imageID'],'measuredHostIdentity':dict(owned,id=allocated['plannedHostIdentity'],hash=a.r.digest(exe)),'measuredClockIdentity':{'clockId':allocated['plannedClockIdentity'],'clockKind':'process-local-stopwatch','frequency':1000,'processID':3,'ticks':1,'utc':'2026-10-11T00:00:01Z','crossProcessQualified':False}};run('measurement',measurement)
 run('snapshotOrder',{'kind':'factory-isolated-uia-parent-ordering-v1','issuedMetadataHash':roles['issuedMetadata']['sha256'][7:],'workerReceiptHash':runs['workerExit']['sha256'][7:],'workerFinalCertificateHash':runs['workerFinal']['sha256'][7:],'snapshotHash':runs['uia']['sha256'][7:],'pixelReceiptHash':runs['pixels']['sha256'][7:],'ownedCloseReceiptHash':runs['close']['sha256'][7:],'pixelSamples':pixels['samples'],'rendererIdentity':owned,'parentProcessID':3,'frequency':1000,'clockDomain':'parent-process-local-stopwatch','crossProcessClockQualified':False,'workerVerifiedTicks':2,'pixelsStartTicks':3,'pixelsEndTicks':4,'ownedCloseStartTicks':5,'ownedCloseEndTicks':6})
 inputs={'roles':roles,'runs':[runs],'metadataRecordPaths':records,'producerSource':{'fixture/capture-plan.json':roles['capturePlan']},'source':{},'runtimeModules':{'fixture.module':raw('module',b'module')}}
 return inputs,store

class Pipeline(unittest.TestCase):
 def invoke(self,mutate=None):
  inputs,store=fixture()
  if mutate:mutate(inputs,store)
  old=a.SUPPORTED_PROFILES
  a.SUPPORTED_PROFILES={inputs['roles']['producerProfile']['sha256']:{'capturePlanHash':inputs['roles']['capturePlan']['sha256']}}
  try:return a.normalize(inputs,lambda ref:store[ref['path']])
  finally:a.SUPPORTED_PROFILES=old
 def test_complete_structural_pipeline(self):
  result=self.invoke();self.assertEqual(result['typedStatus'],'normalized-observational',result['issues']);self.assertEqual(len(result['captures']),1);self.assertFalse(result['qualified'])
 def test_missing_worker_final_does_not_become_capture(self):
  result=self.invoke(lambda i,s:i['runs'][0].pop('workerFinal'));self.assertEqual(result['captures'],[]);self.assertEqual(len(result['diagnosticChannels']),1);self.assertIn('missing-ref:run1:workerFinal',result['issues'])
 def test_hashbound_metadata_cannot_be_swapped(self):
  result=self.invoke(lambda i,s:s.__setitem__('issuedMetadata.json',s['issuedMetadata.json']+b' '));self.assertEqual(result['captures'],[]);self.assertIn('raw-byte-join:issuedMetadata',result['issues'])
 def test_exact_actual_profile_all_bytes(self):
  data=(HERE/'dependencies/producer-stage.json').read_bytes();self.assertIn(a.r.digest(data),a.SUPPORTED_PROFILES)
  for row in a.r.parse(data)['files']:
   data=(REPO/row['path']).read_bytes();self.assertEqual(a.r.digest(data),row['hash']);self.assertEqual(len(data),row['bytes'])
if __name__=='__main__':unittest.main()
