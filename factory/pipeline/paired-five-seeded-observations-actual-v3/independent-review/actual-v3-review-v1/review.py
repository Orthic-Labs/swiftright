#!/usr/bin/env python3
"""Independent offline verification of fresh Mac v3 observations + seeded Windows singles."""
import copy, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
PACKET=ROOT/'factory/pipeline/paired-five-seeded-observations-actual-v3'
MAC=ROOT/'factory/oracle/mac/seed-origin-actual-v1'
WIN=ROOT/'factory/native/windows/round1-seeded-native-v2'
OLDPROOF=WIN/'root-mac-proof-actual-r1/proof-copy.json'
STAGE='2b7ef2e7f2619085b6f6473e741c0579880618152781f144906ecea91dfb4793'
REPORT='590d2e0f00d6e11068f0ba99dd145dc00bc9d4c6394b3d2b47b564073eaa887c'
MACSTAGE='419f334b675f6d19de5db82a4636bf6360c97100834f123cad95cb6b9bb8f832'
SUCCESS='captured-single-observational-uia-printwindow'
CASES={
 'stack':('swiftui.stack-overlay','swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258','single-stack-overlay-r1',33),
 'custom':('swiftui.custom-layout','swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258','single-custom-layout-r1',32),
 'padding':('swiftui.padding-frame','swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258','single-padding-frame-r1',33),
 'preference':('swiftui.preference-key','swiftui.preference-key.recipe.gate-seeded.ca4e13f820f5d258','single-preference-key-r1',33),
 'scroll':('swiftui.scroll-view','swiftui.scroll-view.recipe.gate-seeded.ca4e13f820f5d258','single-scroll-view-r1',34),
}
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def walk(x):
 if isinstance(x,dict):
  yield x
  for y in x.values(): yield from walk(y)
 elif isinstance(x,list):
  for y in x: yield from walk(y)
def need(x,msg):
 if not x: raise ValueError(msg)
def inventory(root):
 fs=[]
 for p in sorted((x for x in root.rglob('*') if x.is_file()),key=lambda x:x.relative_to(root).as_posix()):
  fs.append({'path':p.relative_to(root).as_posix(),'bytes':p.stat().st_size,'sha256':'sha256:'+sha(p)})
 digest=hashlib.sha256(json.dumps(fs,sort_keys=True,separators=(',',':')).encode()).hexdigest()
 return {'root':str(root.relative_to(ROOT)),'exists':root.exists(),'fileCount':len(fs),'bytes':sum(x['bytes'] for x in fs),'inventorySha256':'sha256:'+digest,'files':fs}
def verify_stage():
 sp=PACKET/'stage-manifest.json'; stage=load(sp); need(sha(sp)==STAGE,'producer stage pin')
 expected={x['path']:x for x in stage['files']}; actual={p.name:p for p in PACKET.iterdir() if p.is_file() and p.name!='stage-manifest.json'}
 need(set(expected)==set(actual),'producer stage file list')
 total=0
 for name,p in actual.items():
  e=expected[name]; need(p.stat().st_size==e['bytes'] and 'sha256:'+sha(p)==e['sha256'],'producer stage file '+name); total+=p.stat().st_size
 need(stage['fileCount']==len(actual) and stage['totalBytes']==total,'producer stage denominator')
 need(sha(PACKET/'report.json')==REPORT,'report content pin')
 return {'stageSha256':sha(sp),'reportSha256':sha(PACKET/'report.json'),'files':len(actual),'bytes':total}
def verify(report,live=True):
 need(report['kind']=='f9-paired-five-seeded-observations-actual-v3' and report['version']==3,'report version')
 need(report['candidateOnly'] is True and report['seed']==14577611000270672472,'candidate/seed')
 need(type(report['macFreshRuns']) is int and report['macFreshRuns']==100,'Mac denominator')
 need(type(report['windowsSeedSingles']) is int and report['windowsSeedSingles']==5,'Windows denominator')
 need(type(report['caseCount']) is int and report['caseCount']==5 and set(report['cases'])==set(CASES),'case denominator/set')
 need(report['claims']['legacyMacCaptureProofReused'] is False,'legacy Mac proof reuse')
 need('seed-corrections-v1' not in json.dumps(report['provenance']['macSeedOriginActualV1']),'legacy Mac lineage path')
 need(report['claims']['goldens']==0 and report['claims']['registryPromotion'] is False,'golden/promotion')
 for k in ('nativeExit','nativeParity','qualifiedPaint','qualifiedTiming'):
  need(report['claims'][k]=='held',k+' must stay held')
 need(report['provenance']['compilerOSOrigin']=='Mac main & auxiliary AX compiler receipts admitted; Windows native OS exit remains held','compiler origin scope')
 need(report['accessibility']['roleMap']=={'AXStaticText':'ControlType.Text'},'role map')
 need(report['provenance']['macSeedOriginActualV1']['stageSha256']=='sha256:'+MACSTAGE,'fresh Mac proof stage')
 lineage_p=MAC/'lineage.json'; review_p=MAC/'independent-review/review-report.json'; proc_p=MAC/'independent-review/independent-review-process-receipt.json'
 line=load(lineage_p); review=load(review_p); proc=load(proc_p)
 need(line['kind']=='seed-origin-actual-v1-lineage' and line['status']=='CAPTURED_CANDIDATE_NOT_PROMOTED','fresh lineage status')
 need(line['captureRun'] is True and line['candidateOnly'] is True and line['totalRuns']==100 and line['runsPerCase']==20,'lineage denominators')
 need(review['status']=='PASS' and review['runs']==100 and review['stageSha256']=='sha256:'+MACSTAGE,'fresh independent Mac review')
 need(review['archiveFiles']==2108 and review['stageFiles']==2109 and review['sourceInputPins']==5,'fresh review accounting')
 need(all(review['channelRows'][k]==100 for k in ('compositor','externalAX','instrumented','plain')),'fresh review channels')
 need(all(x=='PASS' for x in review['replayControls'].values()),'fresh Mac replay controls')
 need(proc['exitCode']==0 and proc['stderrSha256']=='sha256:'+hashlib.sha256(b'').hexdigest(),'fresh review process receipt')
 need('sha256:'+sha(proc['stdoutPath'])==proc['stdoutSha256'] and 'sha256:'+sha(proc['stderrPath'])==proc['stderrSha256'],'fresh review process streams')
 pins_path=MAC/'input-snapshot/input-pins.json'; pins=load(pins_path)
 need('sha256:'+sha(pins_path)==line['inputPinsSha256'] and len(pins['rows'])==5,'fresh source input pins')
 need(report['provenance']['macSeedOriginActualV1']['lineage']['sha256']=='sha256:'+sha(lineage_p),'lineage file pin')
 need(report['provenance']['macSeedOriginActualV1']['independentReview']['sha256']=='sha256:'+sha(review_p),'review file pin')
 need(report['provenance']['macSeedOriginActualV1']['reviewProcess']['sha256']=='sha256:'+sha(proc_p),'review process file pin')
 old=load(OLDPROOF); run_total=0; process_pids=set(); instrumented_pids=set(); owner_pids=set(); ax_client_pids=set(); casefacts={}; windows_total=0; broken_receipt_refs={}
 for key,(block,caseid,winname,fetchcount) in CASES.items():
  c=report['cases'][key]; m=c['macFresh100']; w=c['windowsSeedSingle']; linecase=next(x for x in line['cases'] if x['block']==block)
  need(m['path']=='factory/oracle/mac/seed-origin-actual-v1/'+caseid,'fresh Mac case path')
  need(w['path']=='factory/native/windows/round1-seeded-native-v2/'+winname,'Windows path')
  mr=MAC/caseid; summary=load(mr/'summary.json'); compiler=load(mr/'compiler-receipt.json')
  need(summary['case']['id']==linecase['caseId']==m['caseId']==w['caseId']==caseid,'fresh case ID join '+key)
  casehash=summary['case']['hash']; need(m['caseHash']==w['caseHash']==casehash,'fresh case hash join '+key)
  source=MAC/'input-snapshot'/(caseid+'.swift'); sourcehash='sha256:'+sha(source)
  need(m['sourceInput']['path']==str(source.relative_to(ROOT)) and m['sourceInput']['sha256']==sourcehash,'fresh source input '+key)
  need(m['sourceHash']==sourcehash==summary['sourceHash']==linecase['sourceInputSha256'],'source hash/lineage '+key)
  pinrow=next(x for x in pins['rows'] if x['caseID']==caseid)
  need(pinrow['source']['sha256']==sourcehash and pinrow['case']['rawSha256']==casehash,'fresh input pin row '+key)
  need(summary['status']=='CANDIDATE_CAPTURED' and summary['acceptance']=='not-promoted' and summary['candidateOnly'] is True,'Mac observation status '+key)
  need(m['acceptance']=='not-promoted' and m['candidateOnly'] is True,'report Mac status '+key)
  binary=MAC/'archive'/caseid/'binary/capture-host'; bh='sha256:'+sha(binary)
  need(m['binary']['path']==str(binary.relative_to(ROOT)) and m['binary']['sha256']==bh,'fresh executable bytes '+key)
  need(summary['binaryHash']==linecase['binarySha256']==bh and compiler['compiler']['outputBinary']['sha256']==bh,'executable/receipt/lineage '+key)
  cp=mr/'compiler-receipt.json'; comp=compiler['compiler']
  need('sha256:'+sha(cp)==linecase['compilerReceiptSha256']==m['mainCompiler']['receipt']['sha256'],'main compiler receipt hash '+key)
  need(compiler['status']=='SUCCESS' and compiler['sourceDrift'] is False and comp['exitCode']==0 and linecase['compilerExit']==0,'main compiler result '+key)
  need(comp['pid']==comp['pgid']==linecase['compilerPid']==linecase['compilerPgid'],'main compiler process identity '+key)
  process_pids.add(comp['pid'])
  need(m['mainCompiler']['exitCode']==0 and m['mainCompiler']['argv']==comp['argv'] and m['mainCompiler']['cwd']==comp['cwd'],'serialized main compiler identity '+key)
  need(m['summarySha256']=='sha256:'+sha(mr/'summary.json'),'summary hash '+key)
  need(m['rawInventory']==inventory(mr),'full Mac raw inventory '+key)
  need(linecase['status']=='CANDIDATE_CAPTURED' and linecase['sourceDrift'] is False and linecase['toolDrift'] is False,'Mac lineage row '+key)
  need(linecase['manifestSha256']==pinrow['manifest']['sha256'],'case manifest join '+key)
  sourceafter=comp['sourceAfter']; sourcerefs={x['name']:x for x in linecase['sourceBindings']}
  need(set(sourceafter)==set(sourcerefs),'compiler source set '+key)
  report_refs={Path(x['path']).name:x for x in m['mainCompiler']['sourceRefs']}
  need(set(report_refs)==set(sourceafter),'reported compiler source refs '+key)
  for name,value in sourceafter.items():
   ar=MAC/'archive'/caseid/'source'/name
   need(sha(ar)==value['sha256'].removeprefix('sha256:') and value['sha256']==sourcerefs[name]['archiveSha256'],'archived compiler source '+key+'/'+name)
   need(report_refs[name]['sha256']=='sha256:'+sha(ar) and report_refs[name]['bytes']==ar.stat().st_size,'serialized source file ref '+key+'/'+name)
  oldcase=next(x for x in old['cases'] if x['block']==block.removeprefix('swiftui.'))
  case_inst_pids=set(); case_owner_pids=set(); case_ax_pids=set()
  need(len(m['runs'])==20 and len({r['run'] for r in m['runs']})==20,'Mac runs '+key)
  need(len(linecase['runs'])==20 and len(oldcase['runs'])==20,'lineage/legacy denominator '+key)
  for i,row in enumerate(m['runs'],1):
   need(row['run']==i,'Mac run order '+key)
   runroot=mr/f'run-{i:03d}'; runline=next(x for x in linecase['runs'] if x['run']==i); srun=next(x for x in summary['runs'] if x['run']==i)
   for field,pathkey,linekey,summarykey in [('captureSha256','capture.json','captureHash','captureHash'),('rawAXSha256','external-ax.raw.json','externalAXRawHash','externalAXRawHash'),('instrumentedRawSha256','instrumented.raw.json','instrumentedRawHash','instrumented')]:
    actual='sha256:'+sha(runroot/pathkey)
    expect_line=runline[linekey]
    expect_summary=srun[summarykey] if summarykey!='instrumented' else srun['instrumented']['rawHash']
    need(row[field]==actual==expect_line==expect_summary,'Mac raw/lineage/summary '+key+'/'+str(i)+'/'+field)
   need(row['clockSha256']=='sha256:'+sha(runroot/'clock.json'),'clock hash '+key+'/'+str(i))
   clock=load(runroot/'clock.json')
   need(row['timingRaw']==clock,'Mac raw timing '+key+'/'+str(i))
   cap=load(runroot/'capture.json'); inst=load(runroot/'instrumented.raw.json'); ext=load(runroot/'external-ax.raw.json'); owned=load(runroot/'owned-window-process.json')
   need(cap['case']=={'id':caseid,'hash':casehash},'run capture case '+key+'/'+str(i))
   need(bh in [x.get('hash') for x in cap['provenance'].get('inputs',[])],'capture executable provenance '+key+'/'+str(i))
   need(inst['status']==row['rawStatus']==srun['instrumented']['status'],'instrumented status '+key+'/'+str(i))
   need(row['offscreenStatus']==srun['offscreen']==runline['offscreen'],'offscreen status '+key+'/'+str(i))
   need(row['externalAXStatus']==srun.get('externalAX')==runline['externalAX'],'external AX state '+key+'/'+str(i))
   need(ext['pid']==owned['pid'],'AX owner process join '+key+'/'+str(i))
   need(type(inst['pid']) is int and inst['pid']>0 and type(ext['clientPID']) is int and ext['clientPID']>0,'channel process IDs '+key+'/'+str(i))
   need(owned['binaryHash']==bh and ext['ownerHash']==bh and ext['ownerPath']==owned['executable'],'AX owner executable join '+key+'/'+str(i))
   need(ext['clientPID']>0 and owned['client']['binaryHash']==report['provenance']['macCompilerOrigin']['auxiliary']['binary']['sha256'],'AX client executable join '+key+'/'+str(i))
   process_pids.add(inst['pid']); instrumented_pids.add(inst['pid']); owner_pids.add(owned['pid']); ax_client_pids.add(ext['clientPID']); case_inst_pids.add(inst['pid']); case_owner_pids.add(owned['pid']); case_ax_pids.add(ext['clientPID'])
   labels=[x['value'] for x in walk(ext.get('steps',[{}])[0].get('tree',{})) if x.get('role')=='AXStaticText' and isinstance(x.get('value'),str) and x.get('value')!=ext.get('windowTitle')]
   need(labels==row['labels'],'AX text labels '+key+'/'+str(i))
   need(row['instrumentedRawSha256'] != oldcase['runs'][i-1]['rawHash'],'fresh raw differs from legacy proof '+key+'/'+str(i))
   need(row['captureSha256'] != oldcase['runs'][i-1]['captureHash'],'fresh capture differs from legacy proof '+key+'/'+str(i))
  if key=='scroll':
   need(all(x['offscreenStatus']=='HELD' for x in m['runs']),'scroll offscreen held all runs')
   need(report['accessibility']['comparisons'][key]['exactSequenceMatch'] is False and report['accessibility']['comparisons'][key]['qualification']=='held','scroll semantic held')
   need(set(report['accessibility']['comparisons'][key]['macRawStatuses'])=={'UNOBSERVED'},'scroll instrumented unobserved')
   need(report['accessibility']['comparisons'][key]['macValues']==[{'role':'ControlType.Text','value':x} for x in m['runs'][0]['labels']],'scroll retained raw labels')
  elif key=='custom':
   need(report['accessibility']['comparisons'][key]['qualification']=='held' and all(not x['labels'] for x in m['runs']),'custom text unavailable held')
   need(all(x['externalAXStatus']=='HELD' for x in m['runs']),'custom external AX held')
  else:
   compa=report['accessibility']['comparisons'][key]
   need(compa['qualification']=='held' and compa['exactSequenceMatch'] is True,'exact observed labels remain unqualified '+key)
   need(set(compa['macRawStatuses'])=={'OBSERVED'},'observed raw status '+key)
   need(compa['macValues']==[{'role':'ControlType.Text','value':x} for x in m['runs'][0]['labels']],'Mac mapped labels '+key)
  # Existing Windows single observations remain distinct, source/case/executable bound, parity/shutdown held.
  report_review_ref=report['reviewReceipts'][key]
  actual_review_path=WIN/'independent-review/actual-review-f7-v1'/(winname+'.json')
  need(actual_review_path.is_file(),'independent Windows review missing '+key)
  if not (ROOT/report_review_ref).is_file(): broken_receipt_refs[key]={'reportPath':report_review_ref,'expectedPath':str(actual_review_path.relative_to(ROOT))}
  review=load(actual_review_path)
  need(review.get('decision')=='CLEAR-ACTUAL-OBSERVATIONAL-JOINS' and review.get('count')==1,'Windows single review '+key)
  need(review.get('case')=={'id':caseid,'hash':casehash},'Windows review case '+key)
  fetch_ref=review['fetchReceipt']; fetch=load(ROOT/fetch_ref['path'])
  need(sha(ROOT/fetch_ref['path'])==fetch_ref['sha256'] and fetch.get('scpExit')==0 and len(fetch.get('files',[]))==fetchcount,'Windows fetched raw inputs '+key)
  wr=WIN/winname; batch=load(wr/'batch.json'); run=wr/'replays/run-001'; plan=load(run/'plan.json'); obs=load(run/'observation.json'); native=load(run/'native-observation.json'); dispatch=load(run/'dispatch.json'); cap=load(run/'native-01/capture-outcome.json'); uia=load(run/'native-01/native.uia.json'); owned=load(run/'native-01/owned-process.json')
  need(batch['requested']==batch['attempted']==1 and batch['retry'] is False and len(batch['rows'])==1,'Windows one-run denominator '+key)
  need(w['successfulObservations']==1 and w['requested']==w['attempted']==1,'Windows report denominator '+key)
  need(w['rawInventory']==inventory(wr),'full Windows raw inventory '+key)
  need(plan['case']['id']==native['case']['id']==caseid and plan['case']['hash']==native['case']['hash']==casehash==w['caseHash'],'Windows case join '+key)
  need(plan['sourceHash']==obs['sourceHash']==native['sourceHash']==cap['sourceHash']==w['sourceHash'],'Windows source join '+key)
  need(batch['exeHash']==native['exeSha256']==obs['exeSha256']==cap['exeHash']==w['exeHash']==w['row']['exeHash'],'Windows exe join '+key)
  need(native['hostValid'] is True and native['exitCode']==0 and obs['exitCode']==0 and obs['timedOut'] is False,'Windows raw observation success '+key)
  need(dispatch['status']==SUCCESS and batch['rows'][0]['status']==SUCCESS,'Windows captured observation '+key)
  need(w['shutdownQualification']=='held-weak-hasexited-receipt' and w['nativeParity']=='held','Windows weak exit/parity held '+key)
  need(native['nativeParity']=='hold' and native['frozenTupleBound'] is False,'Windows native parity/tuple hold '+key)
  need(obs['cleanupAction']=='natural-exit-no-termination' and obs['ownedExited'] is True,'Windows HasExited-only exit evidence '+key)
  need(w['rawInventory']['files'],'Windows inventory nonempty')
  uia_labels=[n.get('name') for n in walk(uia) if n.get('controlType')=='ControlType.Text' and isinstance(n.get('name'),str)]
  need(uia_labels==w['row']['uiaLabels'],'Windows UIA raw label sequence '+key)
  need(w['row']['uiaSha256']=='sha256:'+sha(run/'native-01/native.uia.json'),'Windows UIA row hash '+key)
  need(w['row']['nativeObservationSha256']=='sha256:'+sha(run/'native-observation.json'),'Windows native observation row hash '+key)
  need(w['row']['pixelsSha256']=='sha256:'+sha(run/'native-01/native.pixels.json'),'Windows pixels row hash '+key)
  need(w['row']['captureOutcomeSha256']=='sha256:'+sha(run/'native-01/capture-outcome.json'),'Windows capture row hash '+key)
  need(w['row']['timingRaw']=={k:obs.get(k) for k in ('startedAt','processStartedAt','finishedAt','timedOut')},'Windows raw timing row '+key)
  if key!='custom':
   need(report['accessibility']['comparisons'][key]['windowsValues']==[{'role':'ControlType.Text','value':x} for x in uia_labels],'Windows mapped comparison '+key)
  else:
   need(uia_labels==[] and report['accessibility']['comparisons'][key]['windowsValues']==[] and report['accessibility']['comparisons'][key]['macValues']==[],'custom UIA/AX text absence')
  windows_total+=1;run_total+=20
  casefacts[key]={'macRuns':20,'freshRawComparedToLegacy':20,'mainCompilerPid':comp['pid'],'instrumentedProcessIds':len(case_inst_pids),'ownerProcessIds':len(case_owner_pids),'externalAXClientProcessIds':len(case_ax_pids),'rawStatuses':sorted({x['rawStatus'] for x in m['runs']}),'offscreenStatuses':sorted({x['offscreenStatus'] for x in m['runs']}),'windowsRuns':1,'windowsShutdownQualification':w['shutdownQualification'],'windowsUILabels':w['row']['uiaLabels'],'qualification':'held'}
 need(run_total==100 and windows_total==5,'global observation denominator')
 need(len(instrumented_pids)==len(owner_pids)==len(ax_client_pids)==100,'100 unique channel process identities')
 aux=report['provenance']['macCompilerOrigin']['auxiliary']; axclient=load(MAC/'fresh-ax-client.json'); axreceipt=load(MAC/'ax-compiler-receipt.json'); auxline=line['auxiliaryAX']
 axsource=MAC/'archive/auxiliary/source/AXClient.swift'; axbinary=MAC/'archive/auxiliary/binary/f5-ax-client'
 need(aux['status']=='SUCCESS' and aux['exitCode']==0 and auxreceipt_matches(aux['compilerReceipt'],MAC/'ax-compiler-receipt.json'),'aux receipt pin')
 need(sha(axsource)==axclient['sourceHash'].removeprefix('sha256:')==auxline['sourceSha256'].removeprefix('sha256:'),'aux source join')
 need(sha(axbinary)==axclient['binaryHash'].removeprefix('sha256:')==auxline['binarySha256'].removeprefix('sha256:'),'aux binary join')
 need(axreceipt['compiler']['exitCode']==auxline['compilerExit']==0 and axreceipt['compiler']['pid']==axreceipt['compiler']['pgid']==auxline['compilerPid']==auxline['compilerPgid'],'aux compiler process join')
 need(aux['binary']['sha256']=='sha256:'+sha(axbinary) and aux['source']['sha256']=='sha256:'+sha(axsource),'serialized aux input hashes')
 need(axclient['permissionRequests'] is False and axclient['externalAX']=='AVAILABLE','AX client preflight')
 need(axclient['compilerReceiptHash']=='sha256:'+sha(MAC/'ax-compiler-receipt.json'),'AX client compiler receipt join')
 need(report['provenance']['fetchCompleteByCase']=={k:v[3] for k,v in CASES.items()},'fetch file counts')
 need(report['rawTiming']['scope']=='raw timestamps & clock hashes retained; no timing claim','raw timing scope')
 for key,c in report['cases'].items():
  need(report['rawTiming']['mac'][key]==[x['timingRaw'] for x in c['macFresh100']['runs']],'Mac timing array '+key)
  need(report['rawTiming']['windows'][key]==c['windowsSeedSingle']['row']['timingRaw'],'Windows timing row '+key)
 return {'ok':True,'brokenWindowsReviewReferences':broken_receipt_refs,'macRuns':run_total,'windowsRuns':windows_total,'caseFacts':casefacts,'legacyProofReuse':'none of 100 raw or capture hashes reused','instrumentedProcessIds':len(instrumented_pids),'ownerProcessIds':len(owner_pids),'externalAXClientProcessIds':len(ax_client_pids),'freshMacReviewStageSha256':MACSTAGE}
def auxreceipt_matches(ref,path): return ref['path']==str(path.relative_to(ROOT)) and ref['sha256']=='sha256:'+sha(path)
def fault_controls(r):
 muts={
  'fresh-source':lambda q:q['cases']['stack']['macFresh100'].__setitem__('sourceHash','sha256:'+'0'*64),
  'fresh-case':lambda q:q['cases']['padding']['macFresh100'].__setitem__('caseHash','sha256:'+'1'*64),
  'fresh-binary':lambda q:q['cases']['custom']['macFresh100']['binary'].__setitem__('sha256','sha256:'+'2'*64),
  'raw-capture':lambda q:q['cases']['stack']['macFresh100']['runs'][0].__setitem__('instrumentedRawSha256','sha256:'+'3'*64),
  'main-process':lambda q:q['cases']['stack']['macFresh100']['mainCompiler'].__setitem__('exitCode',8),
  'old-proof':lambda q:q['claims'].__setitem__('legacyMacCaptureProofReused',True),
  'windows-source':lambda q:q['cases']['scroll']['windowsSeedSingle'].__setitem__('sourceHash','sha256:'+'4'*64),
  'windows-exe':lambda q:q['cases']['preference']['windowsSeedSingle'].__setitem__('exeHash','sha256:'+'5'*64),
  'windows-shutdown':lambda q:q['cases']['stack']['windowsSeedSingle'].__setitem__('shutdownQualification','qualified'),
  'scroll-offscreen':lambda q:q['cases']['scroll']['macFresh100']['runs'][0].__setitem__('offscreenStatus','OBSERVED'),
  'scroll-sequence':lambda q:q['accessibility']['comparisons']['scroll'].__setitem__('exactSequenceMatch',True),
  'custom-ax':lambda q:q['accessibility']['comparisons']['custom'].__setitem__('qualification','qualified'),
  'parity':lambda q:q['claims'].__setitem__('nativeParity','qualified'),
  'timing':lambda q:q['claims'].__setitem__('qualifiedTiming','qualified'),
  'denominator':lambda q:q.__setitem__('macFreshRuns',99),
 }
 out={}
 for name,mut in muts.items():
  t=copy.deepcopy(r);mut(t)
  try:verify(t,live=False)
  except (AssertionError,ValueError,KeyError,TypeError):out[name]='rejected'
  else:out[name]='accepted'
 need(all(x=='rejected' for x in out.values()),'independent fault controls '+repr(out))
 return out
if __name__=='__main__':
 stage=verify_stage();report=load(PACKET/'report.json');res=verify(report);res['stage']=stage;res['independentFaultControls']=fault_controls(report)
 print(json.dumps(res,indent=2,sort_keys=True))
