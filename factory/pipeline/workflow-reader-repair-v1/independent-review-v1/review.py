from pathlib import Path
import json,hashlib,tempfile,importlib.util,inspect
from unittest.mock import patch
from factory.pipeline import workflow as w
from factory.pipeline.archive_reader import ArchiveByteReader
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/pipeline/workflow-reader-repair-v1';O=P/'independent-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def obj(p):return json.loads(p.read_text())
stage=obj(P/'stage-manifest.json')
for row in stage['files']+[stage['source']]:
 p=R/row['path'];assert sha(p)==row['sha256'].removeprefix('sha256:') and p.stat().st_size==row['bytes']
assert sha(R/'factory/pipeline/workflow.py')=='01c15614e9e70737a2da2b8fa1e8c61a95330070796974f768aeaad235dfb2f8'
spec=importlib.util.spec_from_file_location('reader_repair_producer_test',P/'test_reader_repair.py'); t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
producer=t.main();assert producer['baselineCollected']==20 and producer['mutationCollected']==19
before={str(p):sha(p) for p in t.MAC.rglob('*') if p.is_file()}
base=ArchiveByteReader(mac_roots=[R]);seen=[]
class Recording:
 def __call__(self,**kw):
  raw=base(**kw); ref=kw['reference'];assert ref['sha256']=='sha256:'+hashlib.sha256(raw).hexdigest();seen.append(ref['path']);return raw
paths={'plan':R/'factory/pipeline/gate-pilot/gate-results.json','cases':R/'factory/pipeline/inputs/cases.json','tuple':R/'factory/pipeline/inputs/observed-tuple.json','config':R/'factory/pipeline/inputs/acceptance-candidate.json','recipe':R/'factory/recipes/data/swiftui.padding-frame.json','manifest':R/'factory/pipeline/manifests/swiftui.padding-frame.json'}
args=(paths['plan'],paths['cases'],[t.MAC],paths['tuple'],paths['config'],R/'factory/pipeline/manifests')
with tempfile.TemporaryDirectory(prefix='workflow-reader-independent-') as d:
 with patch.object(w,'load_artifact',side_effect=AssertionError('legacy fallback invoked')):
  result=w.gate_evidence(Path(d)/'baseline',*args,origin_reader=ArchiveByteReader(mac_roots=[t.MAC]),artifact_reader=Recording())
assert result['nativeCaptureCount']==20 and not result['parityGranted'] and result['status']=='blocked'
issues=[i for report in result['gateResults'] for i in report['report']['issues']]
assert len([i for i in issues if 'mac-origin:missing-origin' in i])==20
for p in paths.values():assert str(p.resolve()) in seen
faults={}
for label,target in paths.items():
 class Fault:
  def __call__(self,**kw):
   raw=base(**kw)
   if kw['reference']['path']==str(target.resolve()):
    value=json.loads(raw); value={'validJSONFault':value};return json.dumps(value).encode()
   return raw
 with tempfile.TemporaryDirectory(prefix='workflow-reader-fault-') as d:
  try:w.gate_evidence(Path(d)/label,*args,origin_reader=ArchiveByteReader(mac_roots=[t.MAC]),artifact_reader=Fault())
  except ValueError as e:
   assert 'returned bytes differing from expected hash' in str(e);faults[label]=str(e)
  else:raise AssertionError('valid JSON fault accepted: '+label)
assert before=={str(p):sha(p) for p in t.MAC.rglob('*') if p.is_file()}
assert 'artifact_reader' not in inspect.signature(w.prepare).parameters
assert 'origin_reader' in inspect.signature(w.prepare).parameters
report={'verdict':'CLEAR_COLLECT_GATE_EVIDENCE_HASH_BEFORE_PARSE_HOLD_PREPARE_INTERFACE','source':stage['source'],'stageSha256':sha(P/'stage-manifest.json'),'producerControlReplay':producer,'controls':faults,'baseline':{'collected':20,'originAdmitted':0,'parityGranted':False,'exactMissingOriginIssues':20,'legacyFallbackForbidden':'passed'},'readerPaths':sorted(set(seen)),'findings':[{'id':'prepare-callback-separation','proof':'prepare signature lacks artifact_reader; tuple/config/_recipes use origin_reader as artifact reader. Caller cannot supply independent artifact & native-origin callbacks as other workflow branches support. No native guard uses prepare origin_reader.','required':'Add separate artifact_reader to prepare & route _artifact/_recipes through it; preserve omitted-reader defaults.'},{'id':'collect-keyword-documentation','proof':'README says optional artifact_reader on collection; actual collect keyword remains reader. Existing gate/report callers correctly translate artifact_reader to reader.','required':'Document actual collect reader API or add compatible artifact_reader alias.'}], 'scope':['Actual ArchiveByteReader parses verified bytes in collect/gate_evidence; valid JSON rawcapture19+diagnostic & plan/cases/tuple/config/recipe/manifest faults reject precise pre-parse reason','Current file_hash determines expected snapshot; this is per-read integrity, not immutable external allowlist. Caller must close fixed source pins','Schema loader & probe generator witness source reads remain direct disk imports/reads; no all-repository-byte-reader claim made','No raw mutation/native/compiler/remote execution; actual20 collection is not origin admission'], 'rawUnchanged':True}
(O/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps({'report':sha(O/'report.json'),'verdict':report['verdict'],'faultCount':len(faults),'readerFiles':len(set(seen))}))
