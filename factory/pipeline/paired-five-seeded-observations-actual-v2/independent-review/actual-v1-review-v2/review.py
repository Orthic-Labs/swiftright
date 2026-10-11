#!/usr/bin/env python3
"""Independent bounded review of seeded F9 actual-v1, preserving proof mismatch."""
import hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
STAGE=ROOT/'factory/pipeline/paired-five-seeded-observations-actual-v1'
MAC=ROOT/'factory/native/macos/evidence/20261010-gate-seeded'
WIN=ROOT/'factory/native/windows/round1-seeded-native-v2'
PROOF=WIN/'root-mac-proof-actual-r1/proof-copy.json'
LINEAGE=ROOT/'factory/oracle/mac/seed-corrections-lineage-v2/lineage.json'
LINEAGE_REVIEW=ROOT/'factory/oracle/mac/seed-corrections-lineage-v2/independent-review/review.json'
CASES={
 'stack':('swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258','single-stack-overlay-r1','sha256:88ee31aaaba4b6c1729c3530b1461b19167c9e55ee27c72a0124edaea0ec2380','sha256:fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35','stack-overlay'),
 'custom':('swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258','single-custom-layout-r1','sha256:0dba13824f3398666aba1b27b54c01ff02d3e282b2c429a66f3869a05ed0cb49','sha256:00989672411aae376c52781205b826c3e4ae5d6acc52e501a0032996dadcc98d','custom-layout'),
 'padding':('swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258','single-padding-frame-r1','sha256:84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d','sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b','padding-frame'),
 'preference':('swiftui.preference-key.recipe.gate-seeded.ca4e13f820f5d258','single-preference-key-r1','sha256:d908821e18c8ad4e45eed24b446cf3d126fdbf18e17030be45bbbb7105b8459c','sha256:ec6837aefba5cd1b0d550675cb2577030ebc96b61ee5f5ee75a9bd852ca92463','preference-key'),
 'scroll':('swiftui.scroll-view.recipe.gate-seeded.ca4e13f820f5d258','single-scroll-view-r1','sha256:adeed134241b30dfeb873e27dd789b870977457c3b210268f10f3a1be8ffdd18','sha256:27ae712cafa50fd6fd14efe8594a170d26143587dfddc9bbda882dc00c7a4093','scroll-view')}
def sha(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def inv(root):
 fs=[]
 for p in sorted((p for p in root.rglob('*') if p.is_file()),key=lambda p:p.relative_to(root).as_posix()): fs.append({'path':p.relative_to(root).as_posix(),'bytes':p.stat().st_size,'sha256':sha(p)})
 raw=json.dumps(fs,sort_keys=True,separators=(',',':')).encode()
 return {'root':root.relative_to(ROOT).as_posix(),'exists':root.exists(),'fileCount':len(fs),'bytes':sum(x['bytes'] for x in fs),'inventorySha256':'sha256:'+hashlib.sha256(raw).hexdigest(),'files':fs}
def walk(value):
 if isinstance(value,dict):
  yield value
  for child in value.values(): yield from walk(child)
 elif isinstance(value,list):
  for child in value: yield from walk(child)
def ax_labels(raw):
 steps=raw.get('steps',[])
 if not steps:return []
 return [n['value'] for n in walk(steps[0].get('tree',{})) if n.get('role')=='AXStaticText' and isinstance(n.get('value'),str) and n.get('value')!=raw.get('windowTitle')]
def check():
 stage=read(STAGE/'stage-manifest.json'); assert stage['kind']=='f9-paired-five-seeded-observations-actual-v1-stage' and stage['fileCount']==4
 for r in stage['files']:
  p=STAGE/r['path']; assert p.stat().st_size==r['bytes'] and sha(p)==r['sha256']
 report=read(STAGE/'report.json'); pins=read(STAGE/'raw-pins.json'); proof=read(PROOF); lineage=read(LINEAGE); lr=read(LINEAGE_REVIEW)
 assert report['kind']=='f9-paired-five-seeded-observations-actual-v1' and report['seed']==14577611000270672472
 assert report['candidateOnly'] is True and report['macFreshRuns']==100 and report['windowsSeedSingles']==5
 assert report['claims']['nativeParity']==report['claims']['qualifiedParity']==report['claims']['qualifiedPaint']=='held'
 assert report['claims']['compilerOSOrigin']=='missing' and report['claims']['goldens']==0 and report['claims']['registryPromotion'] is False
 assert report['claims']['scrollRaw20'].startswith('UNOBSERVED') and report['rawTiming']['scope']=='raw timestamps & clock hashes retained; no timing claim'
 assert lr['disposition'] and 'held' in str(lr['disposition']).lower()
 proof_cases={r['block']:r for r in proof['cases']}; line_cases={r['block']:r for r in lineage['cases']}
 mismatch=0; capture_mismatch=0; current_summary_join=0; proof_lineage_mismatch=0; external_join=0; capture_join=0; win_total=0; external_status={}; raw_external_status={}; instrumented_status={}
 for key,(mac_id,win_name,case_hash,source_hash,block_suffix) in CASES.items():
  c=report['cases'][key]; mr=c['macFresh100']; wr=c['windowsSeedSingle']; mrroot=MAC/mac_id; wrroot=WIN/win_name
  assert inv(mrroot)==mr['rawInventory']==pins['macRoots'][key]
  assert inv(wrroot)==wr['rawInventory']==pins['windowsRoots'][key]
  summary=read(mrroot/'summary.json'); assert summary['case']=={'id':mac_id,'hash':case_hash}
  assert summary['sourceHash']==summary['provenance']['sourceHash']==summary['probeManifest']['sourceHash']==source_hash
  assert mr['caseId']==mac_id and mr['caseHash']==case_hash and mr['sourceHash']==source_hash and len(mr['runs'])==20
  pc=next(r for r in proof['cases'] if r['block'].endswith(block_suffix)); lc=line_cases[pc['block']]
  assert pc['case']=={'id':mac_id,'hash':case_hash}
  assert pc['witnessHash']==source_hash==lc['sourceWitness']['sha256']
  witness=LINEAGE.parent/lc['sourceWitness']['ownedPath']; assert witness.stat().st_size==lc['sourceWitness']['bytes'] and sha(witness)==source_hash
  pr={x['run']:x for x in pc['runs']}; lruns={x['run']:x for x in lc['rawInstrumentedJoins']}; srows={x['run']:x for x in summary['runs']}; rrows={x['run']:x for x in mr['runs']}
  assert set(pr)==set(lruns)==set(srows)==set(rrows)==set(range(1,21))
  for i in range(1,21):
   rd=mrroot/f'run-{i:03d}'; inst=rd/'instrumented.raw.json'; ext=rd/'external-ax.raw.json'; cap=rd/'capture.json'; sr=srows[i]; rr=rrows[i]
   actual=sha(inst); summary_hash=sr['instrumented']['rawHash']; proof_hash=pr[i]['rawHash']; lineage_hash=lruns[i]['rawSha256']
   assert actual==summary_hash
   current_summary_join += actual==summary_hash
   mismatch += actual!=proof_hash
   proof_lineage_mismatch += proof_hash!=lineage_hash
   assert sha(ext)==sr['externalAXRawHash']==rr['rawAXSha256']; external_join+=1
   cap_hash=sha(cap); assert cap_hash==sr['captureHash']==rr['captureSha256']; capture_join+=1
   capture_mismatch += cap_hash != pr[i]['captureHash']
   capture_doc=read(cap)
   assert capture_doc['case']=={'id':mac_id,'hash':case_hash}
   assert capture_doc['provenance']['producer']=='factory/native/macos' and capture_doc['provenance']['inputs']
   assert rr['externalAXStatus']==sr['externalAX']
   assert read(ext)['status']=='OBSERVED'
   assert rr['labels']==ax_labels(read(ext))
   assert rr['rawStatus']==sr['instrumented']['status']
   external_status[rr['externalAXStatus']]=external_status.get(rr['externalAXStatus'],0)+1
   raw_external_status[read(ext)['status']]=raw_external_status.get(read(ext)['status'],0)+1
   instrumented_status[rr['rawStatus']]=instrumented_status.get(rr['rawStatus'],0)+1
  batch=read(wrroot/'batch.json'); run=wrroot/'replays/run-001'
  assert batch['requested']==batch['attempted']==1 and batch['retry'] is False and len(batch['rows'])==1
  plan,obs,native,dispatch=[read(run/f) for f in ('plan.json','observation.json','native-observation.json','dispatch.json')]
  assert plan['case']==native['case']=={'id':mac_id,'hash':case_hash}
  assert plan['sourceHash']==obs['sourceHash']==native['sourceHash']==wr['sourceHash']==source_hash
  assert batch['rows'][0]['status']==dispatch['status']=='captured-single-observational-uia-printwindow'
  assert obs['exeSha256']==native['exeSha256']==batch['exeHash']==wr['exeHash']
  assert wr['requested']==wr['attempted']==wr['successfulObservations']==1
  assert obs['ownedExited'] is True and obs['exitCode']==0
  ui=read(run/'native-01/native.uia.json')
  win_labels=[n['name'] for n in walk(ui) if n.get('controlType')=='ControlType.Text' and isinstance(n.get('name'),str)]
  assert win_labels==wr['row']['uiaLabels']
  win_total+=1
 assert mismatch==100 and capture_mismatch==100 and proof_lineage_mismatch==0 and current_summary_join==100 and external_join==capture_join==100
 # Scroll's different raw channels stay distinct; label equality is not promoted.
 scroll=report['accessibility']['comparisons']['scroll']
 assert scroll['macRawStatuses']==['UNOBSERVED'] and scroll['exactSequenceMatch'] is False and scroll['qualification']=='held'
 assert {r['rawStatus'] for r in report['cases']['scroll']['macFresh100']['runs']}=={'UNOBSERVED'}
 assert {r['externalAXStatus'] for r in report['cases']['scroll']['macFresh100']['runs']}=={'OBSERVED'}
 assert report['accessibility']['roleMap']=={'AXStaticText':'ControlType.Text'}
 assert report['accessibility']['adapter']=='protected exact AXStaticText to ControlType.Text mapping; no role/name heuristics'
 for key in ('stack','padding','preference'):
  c=report['accessibility']['comparisons'][key]
  assert c['qualification']=='held' and c['exactSequenceMatch'] is True
  assert c['windowsValues']==c['macValues']
 assert report['accessibility']['comparisons']['custom']['qualification']=='held'
 assert report['accessibility']['comparisons']['custom']['qualification']=='held'
 return {'stageManifestSha256':sha(STAGE/'stage-manifest.json'),'decision':'held-proof-raw-join-mismatch','macRuns':100,'windowsSingles':win_total,'currentRawMatchesSummary':current_summary_join,'proofRawMismatches':mismatch,'proofCaptureMismatches':capture_mismatch,'lineageMatchesProof':100-proof_lineage_mismatch,'currentExternalAXAndCaptureJoins':external_join+capture_join,'reportExternalAXStatusCounts':external_status,'rawExternalAXStatusCounts':raw_external_status,'instrumentedStatusCounts':instrumented_status,'nativeTermination':'not established; ownedExited/exitCode are captured fields only','claims':{'compilerOSOrigin':'missing','nativeParity':'held','qualifiedParity':'held','qualifiedPaint':'held','scroll':'instrumented UNOBSERVED; external AX OBSERVED, no cross-channel exact match claim','goldens':0}}
if __name__=='__main__': print(json.dumps(check(),sort_keys=True,indent=2))
