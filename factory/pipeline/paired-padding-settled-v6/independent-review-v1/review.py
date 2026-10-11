from pathlib import Path
import json,hashlib,tempfile,importlib.util
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/pipeline/paired-padding-settled-v6';O=P/'independent-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def obj(p):return json.loads(p.read_text())
s=obj(P/'stage-manifest.json')
for row in s['files']+[s['workflowSource']]:
 p=R/row['path'];assert sha(p)==row['sha256'].removeprefix('sha256:') and p.stat().st_size==row['bytes']
spec=importlib.util.spec_from_file_location('padding_v6_independent',P/'report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
raw_before={str(p):sha(p) for p in m.MAC.rglob('*') if p.is_file()}
rr=m.reader(R);mr=m.reader(m.MAC);cfg,case,recipe,accept=m.source_inputs(rr);f8=m.load_f8(rr);caps,refs=m.mac_captures(mr,f8,cfg,case)
assert caps==obj(P/'root-replay-r1/workflow-gate-evidence/captures.json')==obj(R/'factory/pipeline/paired-padding-settled-v5/root-replay-r1/workflow-gate-evidence/captures.json')
with tempfile.TemporaryDirectory(prefix='paired-padding-v6-independent-') as d:
 out=Path(d); report=m.build(out)
 assert report['macOS']['captures']==caps
 assert obj(out/'workflow-gate-evidence/captures.json')==caps
 assert report['schemaCounts']=={'readerVerified20':True,'schemaCollected20':True,'originVerified':0,'parityQualified':0}
 assert report['integration']['gateMissingOriginExactCode']==20 and report['integration']['notAdmittedWindowsCaptures']==0
 assert report['integration']['compareCase']['status']=='compared' and report['integration']['f9ReportBuilder']['status']=='blocked'
 assert report['integration']['workflowGateEvidence']['status']=='completed'
 assert report['windows']['eligible']==15 and report['windows']['invalidHost']==[3,16] and report['windows']['deadline']==[18] and report['windows']['notStarted']==[19,20]
 assert 'blocked' in (out/'f9/blocks/swiftui.padding-frame.md').read_text()
controls=m.controls();assert controls['gate-missing-origin-count']==20 and controls['duplicate-id']=='rejected'
assert raw_before=={str(p):sha(p) for p in m.MAC.rglob('*') if p.is_file()}
result={'verdict':'CLEAR_SOURCE_BOUND_PARTIAL_V6_REPLAY','producerStageSha256':sha(P/'stage-manifest.json'),'workflowSource':s['workflowSource'],'sourceHash':sha(P/'report.py'),'verifiedFiles':len(s['files']),'counts':report['schemaCounts'],'windowsAdjunct':{'eligible':15,'invalidHost':[3,16],'deadline':[18],'notStarted':[19,20],'typedWindowsCaptures':0},'controlsActualReplay':controls,'verified':['Original Mac20 IDs/envelopes equal v5 & recorded v6 exactly; actual collect/gate/F9 comparator receive original values','Repo-root artifact_reader & Mac-root origin_reader independently passed to production gate_evidence','Exact20 mac-origin:missing-origin issues observed, no native admission/promotion/parity','F8 executes pinned module bytes via temporary file; no separate adapter-function comparison asserted','Raw evidence unchanged'], 'documentationFinding':'README commands still target frozen v5 output/source; replace examples with v6 & fresh output path. Source replay itself correctly uses v6.', 'controlScope':'missing-origin control is real recorded gate observation; Windows adjunct exclusion confirmed actual output typed0. Producer windows observed literal is not standalone adversarial guard control. Prior independent validJSON/hash & duplicate exact-reason controls supplement this packet.'}
(O/'report.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print(sha(O/'report.json'))
