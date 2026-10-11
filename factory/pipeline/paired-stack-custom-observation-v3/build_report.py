#!/usr/bin/env python3
"""F9 v2 consumer: exact source/case joins & per-case Windows fresh20 batches."""
from __future__ import annotations
import copy, hashlib, json, sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
OUT=ROOT/'factory/pipeline/paired-stack-custom-observation-v3'
WIN=ROOT/'factory/native/windows'
ORIGINAL_STACK=WIN/'round1-stack-layout-native-v1/actual-stack-overlay-r1'
ORIGINAL_CUSTOM=WIN/'round1-stack-layout-native-v1/actual-custom-layout-r1'
REPAIRED_STACK=WIN/'round1-native-v3/single-stack-r1/replays/run-001'
FAILED_V1_BATCH=WIN/'round1-stack-layout-repeatability-v1/actual-stack-overlay-r1'
CLEANUP_V2_STACK=WIN/'round1-repeat-cleanup-v2/actual-stack-overlay-r1'
CURRENT=WIN/'round1-native-v3'
MAC_STACK=ROOT/'factory/native/macos/evidence/20261010-primary-five-r3/swiftui.stack-overlay.recipe_case_aac89c30fbc61515'
MAC_CUSTOM=ROOT/'factory/native/macos/evidence/20261010-corrected-primary/swiftui.custom-layout.recipe_case_b30ed0b185e8cb29'
STACK_CASE='sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0'
STACK_SOURCE='sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee'
CUSTOM_CASE='sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a'
CUSTOM_SOURCE='sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b'
SUCCESS='captured-single-observational-uia-printwindow'

def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
 return h.hexdigest()
def load(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def inv(root):
 fs=[]
 if not root.exists(): return {'root':str(root.relative_to(ROOT)),'exists':False,'fileCount':0,'bytes':0,'inventorySha256':None,'files':[]}
 for p in sorted((x for x in root.rglob('*') if x.is_file()),key=lambda x:x.relative_to(root).as_posix()):
  fs.append({'path':p.relative_to(root).as_posix(),'bytes':p.stat().st_size,'sha256':'sha256:'+sha(p)})
 blob=json.dumps(fs,sort_keys=True,separators=(',',':')).encode()
 return {'root':str(root.relative_to(ROOT)),'exists':True,'fileCount':len(fs),'bytes':sum(x['bytes'] for x in fs),'inventorySha256':'sha256:'+hashlib.sha256(blob).hexdigest(),'files':fs}
def attempt_meta(root, case, source, label):
 if not root.exists(): return {'label':label,'path':str(root.relative_to(ROOT)),'available':False,'status':'missing-input'}
 plan=load(root/'plan.json'); obs=load(root/'observation.json'); d=load(root/'dispatch.json'); tr=load(root/'task-result.json')
 assert plan['case']['hash']==case and plan['sourceHash']==source and obs['sourceHash']==source
 return {'label':label,'path':str(root.relative_to(ROOT)),'available':True,'caseHash':case,'sourceHash':source,'planSha256':'sha256:'+sha(root/'plan.json'),'observationSha256':'sha256:'+sha(root/'observation.json'),'dispatchStatus':d.get('status'),'taskStatus':tr.get('status'),'exitCode':obs.get('exitCode'),'nativeParity':obs.get('nativeParity'),'rawInventory':inv(root)}
def validate_single_success(meta, root, case, source):
 assert meta['available'] and meta['caseHash']==case and meta['sourceHash']==source
 n=load(root/'native-observation.json'); px=load(root/'native-01/native.pixels.json'); ui=load(root/'native-01/native.uia.json')
 assert n['sourceHash']==source and n['case']['hash']==case and n['hostValid'] is True and n['exitCode']==0
 assert px['width']==800 and px['height']==600 and px['dpi']==240 and px['printWindowRepeatStable'] is True and px['screenRepeatStable'] is True and px['methodsEqual'] is False
 assert meta['dispatchStatus']==SUCCESS
 return {'nativeObservationSha256':'sha256:'+sha(root/'native-observation.json'),'pixelsSha256':'sha256:'+sha(root/'native-01/native.pixels.json'),'uiaSha256':'sha256:'+sha(root/'native-01/native.uia.json'),'uiaChildren':len(ui.get('children',[])),'printWindowSha256':'sha256:'+sha(root/'native-01/native.printwindow.png'),'repeatSha256':'sha256:'+sha(root/'native-01/native.printwindow.repeat.png'),'width':px['width'],'height':px['height'],'dpi':px['dpi']}
def archive(root, case, source):
 d=load(root/'summary.json'); assert d['case']['hash']==case and d['provenance']['sourceHash']==source and d['probeManifest']['sourceHash']==source and len(d.get('runs',[]))==20
 return {'path':str((root/'summary.json').relative_to(ROOT)),'summarySha256':'sha256:'+sha(root/'summary.json'),'sourceHash':source,'caseHash':case,'runs':20,'acceptance':d.get('acceptance'),'candidateOnly':d.get('candidateOnly'),'inventory':inv(root)}
def batch_meta(root, label, case, source, require20=True, strict=True):
 if not root.exists(): return {'label':label,'expectedPath':str(root.relative_to(ROOT)),'available':False,'status':'awaiting-real-input','caseHash':case,'sourceHash':source,'requested':20,'attempted':0,'qualified':False}
 bpath=root/'batch.json'
 if not bpath.exists(): return {'label':label,'path':str(root.relative_to(ROOT)),'available':True,'status':'rejected-input','reason':'batch.json missing','caseHash':case,'sourceHash':source,'requested':20,'attempted':0,'qualified':False,'rawInventory':inv(root)}
 b=load(bpath); rows=b.get('rows',[]); runs=sorted(root.glob('replays/run-*'))
 result={'label':label,'path':str(root.relative_to(ROOT)),'available':True,'caseHash':case,'sourceHash':source,'status':b.get('status'),'requested':b.get('requested',20),'attempted':b.get('attempted',len(rows)),'retry':b.get('retry'),'rowCount':len(rows),'rawBatchSha256':'sha256:'+sha(bpath),'runCount':len(runs),'qualified':False,'rows':[],'rawInventory':inv(root)}
 errors=[]
 if require20 and b.get('requested')!=20: errors.append('requested-count')
 if require20 and b.get('attempted')!=20: errors.append('attempted-count')
 if require20 and len(rows)!=20: errors.append('row-count')
 expected=set(range(1,21 if require20 else len(rows)+1)); got={r.get('index') for r in rows};
 if got!=expected: errors.append('index-cardinality')
 for i in sorted(expected):
  run=root/f'replays/run-{i:03d}'
  row=next((r for r in rows if r.get('index')==i),None)
  rr={'index':i,'path':str(run.relative_to(ROOT)),'rowStatus':None if row is None else row.get('status'),'available':run.exists()}
  if row is None: errors.append(f'missing-row-{i}')
  if not run.exists(): errors.append(f'missing-run-{i}')
  else:
   try:
    plan=load(run/'plan.json'); obs=load(run/'observation.json'); d=load(run/'dispatch.json'); n=load(run/'native-observation.json'); px=load(run/'native-01/native.pixels.json')
    assert plan['case']['hash']==case and plan['sourceHash']==source and obs['sourceHash']==source and n['sourceHash']==source and n['case']['hash']==case
    assert d.get('status')==SUCCESS and n.get('exitCode')==0 and n.get('hostValid') is True and px.get('width')==800 and px.get('height')==600 and px.get('dpi')==240
    if strict: assert px.get('printWindowRepeatStable') is True and px.get('screenRepeatStable') is True and px.get('methodsEqual') is False
    rr.update(valid=True,planSha256='sha256:'+sha(run/'plan.json'),nativeSha256='sha256:'+sha(run/'native-observation.json'),pixelsSha256='sha256:'+sha(run/'native-01/native.pixels.json'))
   except (AssertionError,KeyError,FileNotFoundError,json.JSONDecodeError) as e:
    errors.append(f'invalid-run-{i}') ; rr.update(valid=False,reason=type(e).__name__)
  result['rows'].append(rr)
 result['errors']=errors
 result['successfulRows']=sum(1 for x in result['rows'] if x.get('rowStatus')==SUCCESS and x.get('valid') is True)
 result['failedRows']=result['rowCount']-result['successfulRows']
 result['qualified']=not errors and result['retry'] is False and result['status'] not in ('hold-batch-error','rejected-input')
 if errors: result['status']='rejected-input'
 return result

def make_report():
 # Exact archives are required before any cross-platform pairing record exists.
 mac={'stack':archive(MAC_STACK,STACK_CASE,STACK_SOURCE),'custom':archive(MAC_CUSTOM,CUSTOM_CASE,CUSTOM_SOURCE)}
 original_failure=attempt_meta(ORIGINAL_STACK,STACK_CASE,STACK_SOURCE,'original-stack-capture-failure')
 original_custom=attempt_meta(ORIGINAL_CUSTOM,CUSTOM_CASE,CUSTOM_SOURCE,'original-custom-single')
 repaired=attempt_meta(REPAIRED_STACK,STACK_CASE,STACK_SOURCE,'repaired-stack-single')
 if repaired['available']: repaired['capture']=validate_single_success(repaired,REPAIRED_STACK,STACK_CASE,STACK_SOURCE)
 failed=batch_meta(FAILED_V1_BATCH,'historical-v1-stack-batch',STACK_CASE,STACK_SOURCE,require20=False,strict=False)
 cleanup_failure=batch_meta(CLEANUP_V2_STACK,'cleanup-v2-stack-failure',STACK_CASE,STACK_SOURCE,require20=False,strict=False)
 current_stack=batch_meta(CURRENT/'repeat-stack-r1','prepared-current-stack',STACK_CASE,STACK_SOURCE)
 current_custom=batch_meta(CURRENT/'repeat-custom-r1','prepared-current-custom',CUSTOM_CASE,CUSTOM_SOURCE)
 return {'kind':'f9-paired-stack-custom-observation-v3','version':3,'candidateOnly':True,'goldens':0,'qualification':'held','parity':'held','mac20':mac,'originalCaptureFailure':original_failure,'historicalV1':{'originalCustom':original_custom,'failedStackBatch':failed,'cleanupV2StackFailure':cleanup_failure},'preparedCurrent':{'repairedStack':repaired,'fresh20Windows':{'stack':current_stack,'custom':current_custom}},'claims':{'fresh20WindowsAvailable':current_stack['qualified'] and current_custom['qualified'],'nativeDiff':'unavailable','shapeLayoutSemantics':'unavailable unless raw provider evidence arrives','excludedAttempts':'none; every attempted historical row retained'},'controls':{'required':['source-mismatch-rejected','case-mismatch-rejected','missing-raw-rejected','batch-count-rejected','forged-status-rejected'],'runner':'build_report.py --fault-controls'}}
def validate(r):
 assert r['kind']=='f9-paired-stack-custom-observation-v3' and r['goldens']==0 and r['qualification']=='held'
 assert r['mac20']['stack']['runs']==20 and r['mac20']['custom']['runs']==20
 assert r['originalCaptureFailure']['caseHash']==STACK_CASE and r['originalCaptureFailure']['sourceHash']==STACK_SOURCE
 assert r['historicalV1']['originalCustom']['caseHash']==CUSTOM_CASE and r['historicalV1']['originalCustom']['sourceHash']==CUSTOM_SOURCE
 b=r['historicalV1']['failedStackBatch']; assert b['available'] and b['requested']==20 and b['attempted']==4 and b['rowCount']==4 and len(b['rows'])==4
 assert r['preparedCurrent']['repairedStack']['available'] and r['preparedCurrent']['repairedStack']['caseHash']==STACK_CASE and r['preparedCurrent']['repairedStack']['sourceHash']==STACK_SOURCE
 cb=r['historicalV1']['cleanupV2StackFailure']; assert cb['available'] and cb['attempted']==1 and cb['qualified'] is False
 for key,case,source in [('stack',STACK_CASE,STACK_SOURCE),('custom',CUSTOM_CASE,CUSTOM_SOURCE)]:
  b=r['preparedCurrent']['fresh20Windows'][key]
  assert b.get('caseHash')==case and b.get('sourceHash')==source
  if b['available'] and b.get('qualified'): assert b['requested']==20 and b['attempted']==20 and b['rowCount']==20 and len(b['rows'])==20
 def walk(x):
  if isinstance(x,dict):
   if 'rawInventory' in x:
    z=x['rawInventory']; fresh=inv(ROOT/z['root']); assert fresh==z
   for v in x.values(): walk(v)
  elif isinstance(x,list):
   for v in x: walk(v)
 walk(r)
 return True
def controls(r):
 assert validate(r); outcomes={}
 muts={'source-mismatch':lambda x:x['preparedCurrent']['repairedStack'].__setitem__('sourceHash','sha256:'+'0'*64),'case-mismatch':lambda x:x['historicalV1']['originalCustom'].__setitem__('caseHash','sha256:'+'1'*64),'missing-raw':lambda x:x['historicalV1']['failedStackBatch']['rawInventory']['files'].pop(),'batch-count':lambda x:x['historicalV1']['failedStackBatch'].__setitem__('attempted',3),'forged-status':lambda x:x.__setitem__('qualification','qualified')}
 for name,mut in muts.items():
  q=copy.deepcopy(r);mut(q)
  try:validate(q)
  except (AssertionError,KeyError):outcomes[name]='rejected'
  else:outcomes[name]='accepted-BUG'
 assert all(v=='rejected' for v in outcomes.values()),outcomes
 return outcomes
def main():
 r=make_report();validate(r)
 if '--fault-controls' in sys.argv: print(json.dumps({'baseline':'accepted','controls':controls(r)},indent=2));return
 (OUT/'report.json').write_text(json.dumps(r,indent=2,sort_keys=True)+'\n')
 roots=[MAC_STACK,MAC_CUSTOM,ORIGINAL_STACK,ORIGINAL_CUSTOM,REPAIRED_STACK,FAILED_V1_BATCH,CLEANUP_V2_STACK]
 for p in [CURRENT/'actual-stack-overlay-r1',CURRENT/'actual-custom-layout-r1']:
  if p.exists():roots.append(p)
 pins={'kind':'f9-v2-raw-input-pins','roots':[inv(x) for x in roots]}
 (OUT/'raw-pins.json').write_text(json.dumps(pins,indent=2,sort_keys=True)+'\n')
 print(json.dumps({'status':'ok','fresh20WindowsAvailable':r['claims']['fresh20WindowsAvailable'],'historicalAttempted':r['historicalV1']['failedStackBatch']['attempted'],'goldens':0},indent=2))
if __name__=='__main__':main()
