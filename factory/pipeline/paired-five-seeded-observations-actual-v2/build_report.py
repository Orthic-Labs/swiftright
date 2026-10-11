#!/usr/bin/env python3
"""Build bounded seeded five-case observation packet from frozen Mac100 & Win seed singles."""
from __future__ import annotations
import copy, hashlib, json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'factory/pipeline/paired-five-seeded-observations-actual-v2'
MACROOT = ROOT / 'factory/oracle/mac/seed-corrections-v1/evidence'
WINROOT = ROOT / 'factory/native/windows/round1-seeded-native-v2'
PROOF = WINROOT / 'root-mac-proof-actual-r1/proof-copy.json'
LINEAGE = ROOT / 'factory/oracle/mac/seed-corrections-lineage-v2/lineage.json'
LINEAGE_REVIEW = ROOT / 'factory/oracle/mac/seed-corrections-lineage-v2/independent-review/review.json'
SEED = 14577611000270672472
PROOF_DATA = None
LINEAGE_DATA = None
PROOF_SHA = 'sha256:9710caa875686a56cde3c0f73f3cf64f357620439ad253bbd6afb0c8bbc53de3'
ROLE_MAP = {'AXStaticText': 'ControlType.Text'}
SUCCESS = 'captured-single-observational-uia-printwindow'
# Order is fixed by seed packet & parent coordination.
CASES = {
 'stack': {'block':'stack-overlay','mac':'swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258','win':'single-stack-overlay-r1','case':'sha256:88ee31aaaba4b6c1729c3530b1461b19167c9e55ee27c72a0124edaea0ec2380','source':'sha256:fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35','fetchComplete':33},
 'custom': {'block':'custom-layout','mac':'swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258','win':'single-custom-layout-r1','case':'sha256:0dba13824f3398666aba1b27b54c01ff02d3e282b2c429a66f3869a05ed0cb49','source':'sha256:00989672411aae376c52781205b826c3e4ae5d6acc52e501a0032996dadcc98d','fetchComplete':32},
 'padding': {'block':'padding-frame','mac':'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258','win':'single-padding-frame-r1','case':'sha256:84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d','source':'sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b','fetchComplete':33},
 'preference': {'block':'preference-key','mac':'swiftui.preference-key.recipe.gate-seeded.ca4e13f820f5d258','win':'single-preference-key-r1','case':'sha256:d908821e18c8ad4e45eed24b446cf3d126fdbf18e17030be45bbbb7105b8459c','source':'sha256:ec6837aefba5cd1b0d550675cb2577030ebc96b61ee5f5ee75a9bd852ca92463','fetchComplete':33},
 'scroll': {'block':'scroll-view','mac':'swiftui.scroll-view.recipe.gate-seeded.ca4e13f820f5d258','win':'single-scroll-view-r1','case':'sha256:adeed134241b30dfeb873e27dd789b870977457c3b210268f10f3a1be8ffdd18','source':'sha256:27ae712cafa50fd6fd14efe8594a170d26143587dfddc9bbda882dc00c7a4093','fetchComplete':34},
}

def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024), b''): h.update(b)
 return h.hexdigest()

def load(p): return json.loads(p.read_text(encoding='utf-8-sig'))

def inv(root):
 fs=[]
 if root.exists():
  for p in sorted((x for x in root.rglob('*') if x.is_file()), key=lambda x:x.relative_to(root).as_posix()):
   fs.append({'path':p.relative_to(root).as_posix(),'bytes':p.stat().st_size,'sha256':'sha256:'+sha(p)})
 raw=json.dumps(fs,sort_keys=True,separators=(',',':')).encode()
 return {'root':str(root.relative_to(ROOT)),'exists':root.exists(),'fileCount':len(fs),'bytes':sum(x['bytes'] for x in fs),'inventorySha256':'sha256:'+hashlib.sha256(raw).hexdigest() if root.exists() else None,'files':fs}

def walk(x):
 if isinstance(x,dict):
  yield x
  for v in x.values(): yield from walk(v)
 elif isinstance(x,list):
  for v in x: yield from walk(v)

def mac_archive(key):
 c=CASES[key]; root=MACROOT/c['mac']; s=load(root/'summary.json')
 proof_case=next(x for x in PROOF_DATA['cases'] if x['block']==c['block'])
 lineage_case=next(x for x in LINEAGE_DATA['cases'] if x['block']==c['block'])
 assert s['case']['id']==c['mac'] and s['case']['hash']==c['case']
 assert s['binaryHash']==lineage_case['binary']['sha256']==proof_case['binaryHash']
 assert s['compiledAdapterHash']==lineage_case['adaptedCaptureHost']['sha256'] and lineage_case['sourceWitness']['sha256']==c['source']
 assert proof_case['case']['id']==c['mac'] and proof_case['case']['hash']==c['case'] and proof_case['witnessHash']==c['source']
 assert s['sourceHash']==c['source'] and s['provenance']['sourceHash']==c['source'] and s['probeManifest']['sourceHash']==c['source']
 assert len(s.get('runs',[]))==20 and s.get('acceptance')=='not-promoted' and s.get('candidateOnly') is True
 rows=[]
 for i in range(1,21):
  rd=root/f'run-{i:03d}'; axp=rd/'external-ax.raw.json'; cap=rd/'capture.json'; clock=rd/'clock.json'
  ax=load(axp); cp=load(cap); match=next((x for x in s['runs'] if x.get('run')==i),None)
  proof_run=next(x for x in proof_case['runs'] if x['run']==i); lineage_run=next(x for x in lineage_case['rawInstrumentedJoins'] if x['run']==i)
  assert match and match.get('externalAXRawHash')=='sha256:'+sha(axp) and match.get('captureHash')=='sha256:'+sha(cap)
  assert proof_run['rawHash']==lineage_run['rawSha256']=='sha256:'+sha(rd/'instrumented.raw.json')
  assert proof_run['captureHash']=='sha256:'+sha(cap)
  assert cp['case']['id']==c['mac'] and cp['case']['hash']==c['case']
  labels=[n.get('value') for n in walk(ax.get('steps',[{}])[0].get('tree',{})) if n.get('role')=='AXStaticText' and isinstance(n.get('value'),str) and n.get('value')!=ax.get('windowTitle')]
  raw_status=match.get('instrumented',{}).get('status','UNKNOWN')
  rows.append({'run':i,'rawAXSha256':'sha256:'+sha(axp),'captureSha256':'sha256:'+sha(cap),'proofRawSha256':proof_run['rawHash'],'instrumentedRawSha256':'sha256:'+sha(rd/'instrumented.raw.json'),'proofCaptureSha256':proof_run['captureHash'],'clockSha256':'sha256:'+sha(clock),'labels':labels,'rawStatus':raw_status,'externalAXStatus':match.get('externalAX'),'ownerPid':ax.get('pid'),'clientPid':ax.get('clientPID'),'timingRaw':load(clock)})
 return {'caseId':c['mac'],'caseHash':c['case'],'sourceHash':c['source'],'path':str(root.relative_to(ROOT)),'summarySha256':'sha256:'+sha(root/'summary.json'),'candidateOnly':True,'acceptance':'not-promoted','fetchComplete':c['fetchComplete'],'runs':rows,'rawInventory':inv(root)}

def native_single(key):
 c=CASES[key]; root=WINROOT/c['win']; batch=load(root/'batch.json'); row=batch['rows'][0]; run=root/'replays/run-001'; nroot=run/'native-01'
 plan,obs,native,dispatch=map(lambda f:load(run/f),['plan.json','observation.json','native-observation.json','dispatch.json'])
 ui=load(nroot/'native.uia.json'); px=load(nroot/'native.pixels.json'); cap=load(nroot/'capture-outcome.json')
 assert batch['requested']==batch['attempted']==1 and batch['retry'] is False and len(batch['rows'])==1
 assert row['status']==SUCCESS and dispatch['status']==SUCCESS
 assert plan['case']['id']==native['case']['id']==c['mac'] and plan['case']['hash']==native['case']['hash']==c['case']
 assert plan['sourceHash']==obs['sourceHash']==native['sourceHash']==c['source']
 assert native['hostValid'] is True and native['exitCode']==0 and obs['exitCode']==0 and obs['timedOut'] is False
 assert obs['exeSha256']==native['exeSha256']==batch['exeHash'] and cap['exeHash']==batch['exeHash'] and cap['sourceHash']==c['source'] and ('sha256:'+cap['macSourceProofHash'])==PROOF_SHA
 assert cap['primaryError']=='' and cap['cleanup']['confirmedOwnedExit'] is True
 assert px['width']==800 and px['height']==600 and px['dpi']==240 and px['printWindowRepeatStable'] is True
 labels=[n.get('name') for n in walk(ui) if n.get('controlType')=='ControlType.Text' and isinstance(n.get('name'),str)]
 return {'mode':'windows-seeded-native-v2-single','path':str(root.relative_to(ROOT)),'batchSha256':'sha256:'+sha(root/'batch.json'),'caseId':c['mac'],'caseHash':c['case'],'sourceHash':c['source'],'exeHash':batch['exeHash'],'compileReceiptHash':batch['compileReceiptHash'],'requested':1,'attempted':1,'successfulObservations':1,'nativeParity':'held','row':{'index':1,'run':'run-001','valid':True,'exeHash':batch['exeHash'],'uiaLabels':labels,'uiaChildren':len(ui.get('children',[])),'uiaSha256':'sha256:'+sha(nroot/'native.uia.json'),'nativeObservationSha256':'sha256:'+sha(run/'native-observation.json'),'pixelsSha256':'sha256:'+sha(nroot/'native.pixels.json'),'captureOutcomeSha256':'sha256:'+sha(nroot/'capture-outcome.json'),'timingRaw':{'startedAt':obs.get('startedAt'),'processStartedAt':obs.get('processStartedAt'),'finishedAt':obs.get('finishedAt'),'timedOut':obs.get('timedOut')}} ,'rawInventory':inv(root)}

def receipt(path, status=None):
 d=load(path) if path.suffix=='.json' else {}
 return {'path':str(path.relative_to(ROOT)),'sha256':'sha256:'+sha(path),'status':status or d.get('decision') or d.get('status')}

def make_report():
 mac={k:mac_archive(k) for k in CASES}; win={k:native_single(k) for k in CASES}
 comps={}
 for k in CASES:
  wl=win[k]['row']['uiaLabels']; ml=mac[k]['runs'][0]['labels']; all_mac_same=all(x['labels']==ml for x in mac[k]['runs'])
  if k=='custom':
   comps[k]={'roleMap':ROLE_MAP,'windowsValues':[],'macValues':[],'macExternalAX':'held: AXHostingView has no AXStaticText','exactSequenceMatch':False,'qualification':'held'}
  elif k=='scroll':
   comps[k]={'roleMap':ROLE_MAP,'windowsValues':[{'role':'ControlType.Text','value':x} for x in wl],'macValues':[{'role':'ControlType.Text','value':x} for x in ml],'macRawStatuses':sorted({x['rawStatus'] for x in mac[k]['runs']}),'exactSequenceMatch':False,'reason':'Mac instrumented raw status UNOBSERVED across 20; labels retained raw only','qualification':'held'}
  else:
   comps[k]={'roleMap':ROLE_MAP,'windowsValues':[{'role':'ControlType.Text','value':x} for x in wl],'macValues':[{'role':'ControlType.Text','value':x} for x in ml],'macRawStatuses':sorted({x['rawStatus'] for x in mac[k]['runs']}),'exactSequenceMatch':all_mac_same and wl==ml,'qualification':'held'}
 return {'kind':'f9-paired-five-seeded-observations-actual-v2','version':2,'candidateOnly':True,'seed':SEED,'caseCount':5,'macFreshRuns':100,'windowsSeedSingles':5,'cases':{k:{'macFresh100':mac[k],'windowsSeedSingle':win[k]} for k in CASES},'accessibility':{'roleMap':ROLE_MAP,'adapter':'protected exact AXStaticText to ControlType.Text mapping; no role/name heuristics','comparisons':comps},'provenance':{'macLineageV2':receipt(LINEAGE),'macLineageIndependentReview':receipt(LINEAGE_REVIEW),'macSourceArchive':{'path':str(MACROOT.relative_to(ROOT)),'kind':'immutable oracle seed-corrections-v1 evidence'},'macSourceProof':{'path':str(PROOF.relative_to(ROOT)),'sha256':'sha256:'+sha(PROOF),'proofHash':PROOF_SHA,'kind':'seed-mac100-two-source-level-join-v2'},'seedNativeRoot':{'path':str(WINROOT.relative_to(ROOT)),'seed':SEED},'compilerOSOrigin':'missing OS process receipt; retained from F7 reviews','fetchCompleteByCase':{k:CASES[k]['fetchComplete'] for k in CASES}},'rawTiming':{'scope':'raw timestamps & clock hashes retained; no timing claim','mac':{k:[r['timingRaw'] for r in mac[k]['runs']] for k in CASES},'windows':{k:win[k]['row']['timingRaw'] for k in CASES}},'claims':{'semantic':'only exact role-mapped labels where source/case pins match & raw status observed','customAX':'held; Windows UIA children empty & Mac AXStaticText unavailable','proofLinkedRawCaptures':100,'proofLinkedCaptureFiles':100,'scrollRaw20':'UNOBSERVED; no cross-host sequence claim','preferenceSeedLabels':'0/1 only; no baseline 0/1/2 assumption','nativeParity':'held','qualifiedPaint':'held','compilerOSOrigin':'missing','qualifiedParity':'held','goldens':0,'registryPromotion':False},'reviewReceipts':{'stack':'factory/native/windows/round1-seeded-native-v2/independent-review/actual-review-f7-v1/single-stack-overlay-r1.json','custom':'factory/native/windows/round1-seeded-native-v2/independent-review/actual-review-f7-v1/single-custom-layout-r1.json','padding':'factory/native/windows/round1-seeded-native-v2/independent-review/actual-review-f7-v1/single-padding-frame-r1.json','preference':'factory/native/windows/round1-seeded-native-v2/independent-review/actual-review-f7-v1/single-preference-key-r1.json','scroll':'pending-review'},'controls':{'runner':'build_report.py --fault-controls','required':['case/source/exe mutation rejected','proof mutation rejected','semantic label mutation rejected','raw inventory mutation rejected','Mac100 denominator mutation rejected','forged parity/qualification mutation rejected']},'rawPins':{'macRoots':{k:mac[k]['rawInventory'] for k in CASES},'windowsRoots':{k:win[k]['rawInventory'] for k in CASES}}}

def validate(r):
 assert r['kind']=='f9-paired-five-seeded-observations-actual-v2' and r['seed']==SEED and r['caseCount']==5 and r['macFreshRuns']==100 and r['windowsSeedSingles']==5
 assert r['claims']['nativeParity']=='held' and r['claims']['qualifiedParity']=='held' and r['claims']['goldens']==0 and r['provenance']['compilerOSOrigin'].startswith('missing')
 assert r['provenance']['macSourceProof']['proofHash']==PROOF_SHA and r['provenance']['macLineageV2']['sha256']=='sha256:'+sha(LINEAGE)
 assert all(all(x['proofRawSha256']==x['instrumentedRawSha256'] for x in r['cases'][k]['macFresh100']['runs']) for k in CASES)
 assert all(all(x['proofCaptureSha256']==x['captureSha256'] for x in r['cases'][k]['macFresh100']['runs']) for k in CASES)
 assert all(all(x['rawStatus'] in ('OBSERVED','UNOBSERVED') for x in r['cases'][k]['macFresh100']['runs']) for k in CASES)
 assert r['provenance']['fetchCompleteByCase']=={'stack':33,'custom':32,'padding':33,'preference':33,'scroll':34}
 for k,c in CASES.items():
  m=r['cases'][k]['macFresh100']; w=r['cases'][k]['windowsSeedSingle']
  assert len(m['runs'])==20 and m['rawInventory']==inv(MACROOT/c['mac']) and m['caseHash']==c['case'] and m['sourceHash']==c['source']
  assert w['successfulObservations']==1 and w['caseHash']==c['case'] and w['sourceHash']==c['source'] and w['rawInventory']==inv(WINROOT/c['win'])
  assert w['row']['valid'] and w['exeHash']==w['row']['exeHash'] and w['row']['uiaSha256']=='sha256:'+sha(WINROOT/c['win']/'replays/run-001/native-01/native.uia.json')
 for k in ('stack','padding','preference'):
  assert r['accessibility']['comparisons'][k]['exactSequenceMatch'] is True
 for k in CASES:
  if k!='custom':
   assert r['accessibility']['comparisons'][k]['windowsValues']==[{'role':'ControlType.Text','value':x} for x in r['cases'][k]['windowsSeedSingle']['row']['uiaLabels']]
 assert r['accessibility']['comparisons']['custom']['qualification']=='held' and r['accessibility']['comparisons']['scroll']['exactSequenceMatch'] is False
 assert all(len(x['labels'])==0 for x in r['cases']['custom']['macFresh100']['runs'])
 assert all(x['rawStatus']=='UNOBSERVED' for x in r['cases']['scroll']['macFresh100']['runs'])
 return True

def controls(r):
 validate(r); out={}
 muts={'source':lambda q:q['cases']['stack']['windowsSeedSingle'].__setitem__('sourceHash','sha256:'+'0'*64),'case':lambda q:q['cases']['padding']['windowsSeedSingle'].__setitem__('caseHash','sha256:'+'1'*64),'exe':lambda q:q['cases']['scroll']['windowsSeedSingle'].__setitem__('exeHash','0'*64),'proof':lambda q:q['provenance']['macSourceProof'].__setitem__('proofHash','sha256:'+'2'*64),'semantic':lambda q:q['accessibility']['comparisons']['preference']['windowsValues'].__setitem__(0,{'role':'ControlType.Text','value':'forged'}),'raw':lambda q:q['cases']['custom']['windowsSeedSingle']['rawInventory']['files'].pop(),'denominator':lambda q:q.__setitem__('macFreshRuns',99),'qualification':lambda q:q['claims'].__setitem__('qualifiedParity','qualified')}
 for name,mut in muts.items():
  q=copy.deepcopy(r); mut(q)
  try: validate(q)
  except (AssertionError,KeyError): out[name]='rejected'
  else: out[name]='accepted-BUG'
 assert all(v=='rejected' for v in out.values()),out
 return out

def stage():
 fs=[]
 for p in sorted(x for x in OUT.iterdir() if x.is_file() and x.name!='stage-manifest.json'):
  fs.append({'path':p.name,'bytes':p.stat().st_size,'sha256':'sha256:'+sha(p)})
 assert all(x['bytes']<100*1024*1024 for x in fs)
 return {'kind':'f9-paired-five-seeded-observations-actual-v2-stage','fileCount':len(fs),'totalBytes':sum(x['bytes'] for x in fs),'files':fs}

def main():
 global PROOF_DATA, LINEAGE_DATA
 PROOF_DATA=load(PROOF); LINEAGE_DATA=load(LINEAGE)
 r=make_report(); validate(r)
 if '--fault-controls' in sys.argv:
  print(json.dumps({'baseline':'accepted','controls':controls(r)},indent=2)); return
 (OUT/'report.json').write_text(json.dumps(r,indent=2,sort_keys=True)+'\n')
 (OUT/'raw-pins.json').write_text(json.dumps(r['rawPins'],indent=2,sort_keys=True)+'\n')
 (OUT/'README.md').write_text('# Paired five seeded observations actual v2\n\nImmutable oracle seed-corrections-v1 Mac archive contributes 100 proof-linked raw/capture runs through lineage-v2/proof 9710; each proof hash is checked against immutable file bytes. Windows seed-native-v2 contributes one actual observational run per case. Source, case, executable & proof joins are strict. AXStaticText maps only to ControlType.Text; custom AX is held, scroll raw 20 is UNOBSERVED, preference seed exposes 0/1 only. Compiler OS origin, qualified parity, paint, timing qualification & goldens remain held; raw timing stays separate.\n')
 (OUT/'stage-manifest.json').write_text(json.dumps(stage(),indent=2,sort_keys=True)+'\n')
 print(json.dumps({'status':'ok','macFreshRuns':100,'windowsSeedSingles':5,'scrollRawStatus':'UNOBSERVED','goldens':0},indent=2))
if __name__=='__main__': main()
