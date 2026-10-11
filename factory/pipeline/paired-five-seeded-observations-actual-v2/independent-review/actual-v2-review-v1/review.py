#!/usr/bin/env python3
"""Independent offline audit of frozen paired-five-seeded-observations actual v2."""
import copy, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
PACKET=ROOT/'factory/pipeline/paired-five-seeded-observations-actual-v2'
EXPECTED_STAGE='91d219406e4dfbdccb7c7aa0b804c140adef39bf3bd5812b7906308e7e7f0374'
EXPECTED_PROOF_FILE='338beb9af290f19b5657c1c5cef3f5b83d5f9da29545b0b939f4c023a51e538f'
EXPECTED_PROOF_ID='9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3'
EXPECTED_LINEAGE='18ccbd'
CASES={
 'stack':('stack-overlay','swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258','fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35','88ee31aaaba4b6c1729c3530b1461b19167c9e55ee27c72a0124edaea0ec2380','factory/native/windows/round1-seeded-native-v2/single-stack-overlay-r1'),
 'custom':('custom-layout','swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258','00989672411aae376c52781205b826c3e4ae5d6acc52e501a0032996dadcc98d','0dba13824f3398666aba1b27b54c01ff02d3e282b2c429a66f3869a05ed0cb49','factory/native/windows/round1-seeded-native-v2/single-custom-layout-r1'),
 'padding':('padding-frame','swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258','b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b','84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d','factory/native/windows/round1-seeded-native-v2/single-padding-frame-r1'),
 'preference':('preference-key','swiftui.preference-key.recipe.gate-seeded.ca4e13f820f5d258','ec6837aefba5cd1b0d550675cb2577030ebc96b61ee5f5ee75a9bd852ca92463','d908821e18c8ad4e45eed24b446cf3d126fdbf18e17030be45bbbb7105b8459c','factory/native/windows/round1-seeded-native-v2/single-preference-key-r1'),
 'scroll':('scroll-view','swiftui.scroll-view.recipe.gate-seeded.ca4e13f820f5d258','27ae712cafa50fd6fd14efe8594a170d26143587dfddc9bbda882dc00c7a4093','adeed134241b30dfeb873e27dd789b870977457c3b210268f10f3a1be8ffdd18','factory/native/windows/round1-seeded-native-v2/single-scroll-view-r1'),
}
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def load(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def walk(x):
 if isinstance(x,dict):
  yield x
  for v in x.values(): yield from walk(v)
 elif isinstance(x,list):
  for v in x: yield from walk(v)
def need(ok,msg):
 if not ok: raise ValueError(msg)
def verify(r,check_live=True):
 need(r.get('kind')=='f9-paired-five-seeded-observations-actual-v2','kind')
 need(r.get('seed')==14577611000270672472 and type(r.get('seed')) is int,'seed')
 need(r.get('caseCount')==5 and type(r.get('caseCount')) is int,'caseCount')
 need(r.get('macFreshRuns')==100 and type(r.get('macFreshRuns')) is int,'Mac denominator')
 need(r.get('windowsSeedSingles')==5 and type(r.get('windowsSeedSingles')) is int,'Windows denominator')
 need(set(r['cases'])==set(CASES),'case set')
 need(r['candidateOnly'] is True,'candidateOnly')
 need(r['claims']['goldens']==0 and r['claims']['registryPromotion'] is False,'promotion/golden')
 need(r['claims']['nativeParity']=='held' and r['claims']['qualifiedParity']=='held' and r['claims']['qualifiedPaint']=='held','qualification')
 need(r['provenance']['compilerOSOrigin']=='missing OS process receipt; retained from F7 reviews','compiler origin')
 need(r['accessibility']['roleMap']=={'AXStaticText':'ControlType.Text'},'role map')
 proof=ROOT/'factory/native/windows/round1-seeded-native-v2/root-mac-proof-actual-r1/proof-copy.json'
 lineage=ROOT/'factory/oracle/mac/seed-corrections-lineage-v2/lineage.json'
 lineage_review=ROOT/'factory/oracle/mac/seed-corrections-lineage-v2/independent-review/review.json'
 need(sha(proof)==EXPECTED_PROOF_FILE,'proof file bytes')
 need(r['provenance']['macSourceProof']['sha256']=='sha256:'+EXPECTED_PROOF_FILE,'proof sidecar')
 need(r['provenance']['macLineageV2']['sha256']=='sha256:'+sha(lineage),'lineage bytes')
 need(sha(lineage).startswith(EXPECTED_LINEAGE),'lineage expected lineage')
 need(r['provenance']['macLineageIndependentReview']['sha256']=='sha256:'+sha(lineage_review),'lineage review bytes')
 pd=load(proof); ld=load(lineage)
 need(r['provenance']['macSourceProof']['proofHash']=='sha256:'+EXPECTED_PROOF_ID,'proof identity')
 total_mac=0; total_win=0; casefacts={}
 for key,(block,macid,source,casehash,win_rel) in CASES.items():
  c=r['cases'][key]; m=c['macFresh100']; w=c['windowsSeedSingle']
  need(m['path']=='factory/oracle/mac/seed-corrections-v1/evidence/'+macid,'Mac source archive path')
  need(w['path']==win_rel,'Win source path')
  need(m['caseId']==macid and w['caseId']==macid and m['caseHash']==w['caseHash']=='sha256:'+casehash,'case identity')
  need(m['sourceHash']=='sha256:'+source and w['sourceHash']=='sha256:'+source,'source hash')
  need(len(m['runs'])==20 and len({x['run'] for x in m['runs']})==20,'20 Mac runs')
  need(w['requested']==w['attempted']==w['successfulObservations']==1,'one Win observation')
  need(w['row']['valid'] is True,'Win row valid')
  need(w['nativeParity']=='held','Win native parity')
  receipt_ref=r['reviewReceipts'][key]
  if receipt_ref!='pending-review':
   receipt_path=ROOT/receipt_ref
   receipt=load(receipt_path)
   need(receipt.get('decision')=='CLEAR-ACTUAL-OBSERVATIONAL-JOINS','Windows observation review '+key)
   need(receipt.get('case')=={'id':macid,'hash':'sha256:'+casehash},'Windows review case '+key)
   fetch_path=ROOT/receipt['fetchReceipt']['path']
   fetch=load(fetch_path)
   need(sha(fetch_path)==receipt['fetchReceipt']['sha256'],'Windows fetch receipt hash '+key)
  else:
   # Scroll receipt is intentionally pending in report. Existing fetch log is auxiliary corroboration only.
   fetch_path=ROOT/'factory/native/windows/round1-seeded-native-v2/root-single-scroll-output-scp.json'
   fetch=load(fetch_path)
  need(fetch.get('scpExit')==0 and len(fetch.get('files',[]))==m['fetchComplete'],'fetch-complete file count '+key)
  need(r['provenance']['fetchCompleteByCase'][key]==m['fetchComplete'],'fetch count report join '+key)
  proof_case=next(x for x in pd['cases'] if x['block']==block)
  lineage_case=next(x for x in ld['cases'] if x['block']==block)
  need(proof_case['case']['id']==macid and proof_case['case']['hash']=='sha256:'+casehash,'proof case/source join')
  need(proof_case['witnessHash']=='sha256:'+source,'proof witness join')
  need(lineage_case['caseID']==macid and lineage_case['caseHash']=='sha256:'+casehash and lineage_case['sourceWitness']['sha256']=='sha256:'+source,'lineage case/source join')
  need(proof_case['binaryHash']==lineage_case['binary']['sha256'],'Mac binary join')
  need(w['exeHash']==w['row']['exeHash'] and w['exeHash'] != '','Windows executable join')
  macroot=ROOT/m['path']; winroot=ROOT/w['path']; macsummary=load(macroot/'summary.json')
  if check_live:
   for invroot,inventory in ((macroot,m['rawInventory']),(winroot,w['rawInventory'])):
    need(invroot.is_dir(),'inventory root missing '+str(invroot))
    actual=[]
    for f in sorted((x for x in invroot.rglob('*') if x.is_file()),key=lambda x:x.relative_to(invroot).as_posix()):
     actual.append({'path':f.relative_to(invroot).as_posix(),'bytes':f.stat().st_size,'sha256':'sha256:'+sha(f)})
    need(actual==inventory['files'],'raw inventory mismatch '+str(invroot))
    need(inventory['fileCount']==len(actual) and inventory['bytes']==sum(x['bytes'] for x in actual),'inventory counts '+str(invroot))
    invbytes=json.dumps(actual,sort_keys=True,separators=(',',':')).encode()
    need(inventory['inventorySha256']=='sha256:'+hashlib.sha256(invbytes).hexdigest(),'inventory digest '+str(invroot))
  for idx,row in enumerate(m['runs'],1):
   need(row['run']==idx,'run order')
   proof_run=next(x for x in proof_case['runs'] if x['run']==idx)
   line_run=next(x for x in lineage_case['rawInstrumentedJoins'] if x['run']==idx)
   need(row['proofRawSha256']==row['instrumentedRawSha256']==proof_run['rawHash']==line_run['rawSha256'],'raw proof join '+key+'/'+str(idx))
   need(row['captureSha256']==row['proofCaptureSha256']==proof_run['captureHash'],'capture proof join '+key+'/'+str(idx))
   runroot=macroot/f'run-{idx:03d}'
   if check_live:
    need('sha256:'+sha(runroot/'instrumented.raw.json')==row['instrumentedRawSha256'],'raw file bytes '+key+'/'+str(idx))
    need('sha256:'+sha(runroot/'capture.json')==row['captureSha256'],'capture bytes '+key+'/'+str(idx))
    need('sha256:'+sha(runroot/'external-ax.raw.json')==row['rawAXSha256'],'AX bytes '+key+'/'+str(idx))
    need('sha256:'+sha(runroot/'clock.json')==row['clockSha256'],'clock bytes '+key+'/'+str(idx))
    raw=load(runroot/'instrumented.raw.json'); ax=load(runroot/'external-ax.raw.json'); cap=load(runroot/'capture.json')
    need(cap['case']['id']==macid and cap['case']['hash']=='sha256:'+casehash,'capture case '+key+'/'+str(idx))
    # Raw instrumented and external AX are distinct sources; don't infer from one another.
    need(row['rawStatus']==raw.get('status'),'instrumented status '+key+'/'+str(idx))
    summary_run=next(x for x in macsummary['runs'] if x.get('run')==idx)
    need(row['externalAXStatus']==summary_run.get('externalAX'),'summary external AX status '+key+'/'+str(idx))
    need(ax.get('status') in ('OBSERVED','UNOBSERVED','HELD'),'raw external AX status '+key+'/'+str(idx))
    need(row['labels']==[n['value'] for n in walk(ax.get('steps',[{}])[0].get('tree',{})) if n.get('role')=='AXStaticText' and isinstance(n.get('value'),str) and n.get('value')!=ax.get('windowTitle')],'AX labels '+key+'/'+str(idx))
  total_mac+=len(m['runs'])
  if check_live:
   runroot=winroot/'replays/run-001'; nroot=runroot/'native-01'
   uia=load(nroot/'native.uia.json'); obs=load(runroot/'observation.json'); native=load(runroot/'native-observation.json'); cap=load(nroot/'capture-outcome.json')
   plan=load(runroot/'plan.json'); batch=load(winroot/'batch.json')
   need(batch['requested']==batch['attempted']==1 and batch['retry'] is False and len(batch['rows'])==1,'single no-retry '+key)
   need(plan['case']['id']==native['case']['id']==macid and plan['case']['hash']==native['case']['hash']=='sha256:'+casehash,'Win case join '+key)
   need(plan['sourceHash']==obs['sourceHash']==native['sourceHash']=='sha256:'+source,'Win source joins '+key)
   need(obs['exeSha256']==native['exeSha256']==batch['exeHash']==w['exeHash'],'Win exe joins '+key)
   need(cap['exeHash']==w['exeHash'] and cap['sourceHash']=='sha256:'+source,'Win capture joins '+key)
   need(cap['macSourceProofHash']==EXPECTED_PROOF_ID,'Win proof join '+key)
   labels=[n.get('name') for n in walk(uia) if n.get('controlType')=='ControlType.Text' and isinstance(n.get('name'),str)]
   need(labels==w['row']['uiaLabels'],'Win UIA label join '+key)
   need('qualified' not in json.dumps(w).lower(),'Win qualified native claim')
  expected=r['accessibility']['comparisons'][key]
  need(expected['qualification']=='held','case qualification held '+key)
  if key=='custom':
   need(expected['windowsValues']==[] and expected['macValues']==[] and 'no AXStaticText' in expected['macExternalAX'],'custom empty/held')
  elif key=='scroll':
   need(expected['exactSequenceMatch'] is False and set(expected['macRawStatuses'])=={'UNOBSERVED'},'scroll instrumented status')
   need(expected['reason'].startswith('Mac instrumented raw status UNOBSERVED'),'scroll reason')
  else:
   need(expected['roleMap']=={'AXStaticText':'ControlType.Text'} and expected['exactSequenceMatch'] is True,'exact role-mapped observation '+key)
   need(expected['macRawStatuses']==['OBSERVED'],'observed instrumented status '+key)
  casefacts[key]={'macRuns':len(m['runs']),'windowsRuns':w['successfulObservations'],'macRawStatuses':sorted({x['rawStatus'] for x in m['runs']}),'externalAXStatuses':sorted({x['externalAXStatus'] for x in m['runs']}),'windowsLabels':w['row']['uiaLabels'],'qualification':expected['qualification']}
  total_win+=w['successfulObservations']
 need(total_mac==100 and total_win==5,'overall denominators')
 need(r['claims']['proofLinkedRawCaptures']==100 and r['claims']['proofLinkedCaptureFiles']==100,'claim denominators')
 return {'ok':True,'caseFacts':casefacts,'macRuns':total_mac,'windowsRuns':total_win,'proofFileSha256':sha(proof),'proofIdentity':'sha256:'+EXPECTED_PROOF_ID,'lineageSha256':sha(lineage)}
def negative_controls(r):
 muts={
  'case-hash':lambda q:q['cases']['stack']['macFresh100'].__setitem__('caseHash','sha256:'+'0'*64),
  'source-hash':lambda q:q['cases']['padding']['windowsSeedSingle'].__setitem__('sourceHash','sha256:'+'1'*64),
  'exe':lambda q:q['cases']['scroll']['windowsSeedSingle'].__setitem__('exeHash','sha256:'+'2'*64),
  'proof-row':lambda q:q['cases']['stack']['macFresh100']['runs'][0].__setitem__('proofRawSha256','sha256:'+'3'*64),
  'mac-denominator':lambda q:q.__setitem__('macFreshRuns',99),
  'win-denominator':lambda q:q.__setitem__('windowsSeedSingles',4),
  'scroll-unobserved':lambda q:q['accessibility']['comparisons']['scroll'].__setitem__('macRawStatuses',['OBSERVED']),
  'custom-empty':lambda q:q['accessibility']['comparisons']['custom'].__setitem__('qualification','qualified'),
  'role-map':lambda q:q['accessibility']['comparisons']['padding']['roleMap'].__setitem__('AXStaticText','ControlType.Button'),
  'golden':lambda q:q['claims'].__setitem__('goldens',1),
 }
 result={}
 for name,mut in muts.items():
  altered=copy.deepcopy(r); mut(altered)
  try: verify(altered,check_live=False)
  except (ValueError,AssertionError,KeyError,TypeError): result[name]='rejected'
  else: result[name]='accepted'
 need(all(v=='rejected' for v in result.values()),'fault controls '+repr(result))
 return result
def verify_stage():
 stage_path=PACKET/'stage-manifest.json'; stage=load(stage_path)
 need(sha(stage_path)==EXPECTED_STAGE,'stage manifest hash')
 listed={item['path']:item for item in stage['files']}
 actual={p.name:p for p in PACKET.iterdir() if p.is_file() and p.name!='stage-manifest.json'}
 need(set(listed)==set(actual),'stage file set')
 total=0
 for name,p in actual.items():
  entry=listed[name]
  need(p.stat().st_size==entry['bytes'] and 'sha256:'+sha(p)==entry['sha256'],'stage file pin '+name)
  total+=p.stat().st_size
 need(stage['fileCount']==len(actual) and stage['totalBytes']==total,'stage counts')
 return {'stageSha256':sha(stage_path),'stageFiles':len(actual),'stageBytes':total}
if __name__=='__main__':
 stage=verify_stage()
 report=load(PACKET/'report.json')
 result=verify(report)
 result['stage']=stage
 result['faultControls']=negative_controls(report)
 print(json.dumps(result,indent=2,sort_keys=True))
