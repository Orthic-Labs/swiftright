from pathlib import Path
import json, hashlib, importlib.util, tempfile, copy, sys
from unittest.mock import patch
R=Path('/Volumes/D/claude/swiftright'); P=R/'factory/pipeline/paired-padding-settled-v5'; O=P/'independent-review-v1'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p): return json.loads(p.read_text())
def verify(rows,base):
 for x in rows:
  p=base/x['path']; assert sha(p)==x['sha256'].removeprefix('sha256:'), str(p)
  assert p.stat().st_size==x['bytes'], str(p)
 return len(rows)
a=load(P/'stage-manifest.json'); b=load(P/'root-replay-r1/stage-manifest.json')
counts={'producerFiles':verify(a['files'],P),'replayFiles':verify(b['outputFiles'],R),'productionDependencies':verify(b['productionDependencies'],R)}
assert sha(P/'stage-manifest.json')==b['frozenV5StageSha256'].removeprefix('sha256:')
assert sha(P/'report.py')=='b66b8dd1d28b05889907096c24c0de978b25a0eab756aa96982ad3fa1ac07d52'
spec=importlib.util.spec_from_file_location('paired_padding_v5_review',P/'report.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
from factory.pipeline import workflow
from factory.pipeline.archive_reader import ArchiveByteReader, ArchiveReadError
before={str(p):sha(p) for p in m.MAC.rglob('*') if p.is_file()}
rr=m.reader(R); mr=m.reader(m.MAC); cfg,case,recipe,accept=m.source_inputs(rr); adapter=m.load_f8(rr); caps,refs=m.mac_captures(mr,adapter,cfg,case)
assert len(caps)==20 and len({c['id'] for c in caps})==20
actual=load(P/'root-replay-r1/workflow-gate-evidence/captures.json'); assert actual==caps
assert m.workflow_collect(case,mr,O)['captures']==caps
comp=m.compare_actual(case,caps,accept); assert comp['status']=='compared'
dup=copy.deepcopy(caps); dup[1]['id']=dup[0]['id']; rejected=m.compare_actual(case,dup,accept)
assert rejected['status']=='blocked' and rejected['error']=='capture IDs must be present and unique', rejected
# Reader rejects byte drift BEFORE invalid JSON parsing; fixture is valid JSON on both sides.
with tempfile.TemporaryDirectory(prefix='paired-padding-reader-review-') as d:
 p=Path(d)/'valid.json'; original=b'{"value":1}'; p.write_bytes(original)
 reader=ArchiveByteReader(mac_roots=[Path(d)])
 ref={'path':str(p),'sha256':'sha256:'+hashlib.sha256(original).hexdigest()}
 assert reader(capture={'platform':'macos'},reference=ref)==original
 p.write_bytes(b'{"value":2}')
 try: reader(capture={'platform':'macos'},reference=ref)
 except ArchiveReadError as e: reader_fault=str(e)
 else: raise AssertionError('reader accepted drift')
 assert 'hash' in reader_fault.lower(), reader_fault
# Actual workflow reread accepts schema-valid changed ID after original reader verification.
original_load=workflow.load_artifact
first=m.MAC/'run-001/capture.json'
def changed_load(path):
 value=original_load(path)
 if Path(path)==first:
  value=copy.deepcopy(value); value['id']=value['id']+'.independent-reread-fault'
 return value
with patch.object(workflow,'load_artifact',side_effect=changed_load):
 changed=m.workflow_collect(case,mr,O)
assert changed['status']=='collected' and changed['count']==20
assert changed['captures'][0]['id']!=caps[0]['id']
# Module provenance & actual origin holds.
provenance={}
for name in ['factory.pipeline.workflow','factory.pipeline.archive_reader','factory.comparison.comparator','factory.reports.report','factory.gate.core','factory.core.artifacts','factory.tools.schema_validate']:
 module=sys.modules[name]; p=Path(module.__file__).resolve(); assert p.is_relative_to(R)
 provenance[name]={'path':str(p.relative_to(R)),'sha256':sha(p)}
gate=load(P/'root-replay-r1/workflow-gate-evidence/gate-results.json')
assert gate['nativeCaptureCount']==20 and gate['status']=='blocked' and gate['parityGranted'] is False
reports=[x['report'] for x in gate['gateResults']]; assert all(x['status']=='blocked' and x['parityGranted'] is False for x in reports)
issues=[i for x in reports for i in x['issues']]
origin_issues=[x for x in issues if 'origin' in x.lower()]
assert origin_issues, 'expected historic origin holds'
r=load(P/'root-replay-r1/report.json'); assert r['schemaCounts']=={'originVerified':0,'parityQualified':0,'readerVerified20':True,'schemaCollected20':True}
assert r['windows']['eligible']==15 and r['windows']['invalidHost']==[3,16] and r['windows']['deadline']==[18] and r['windows']['notStarted']==[19,20]
assert all('origin' not in c for c in caps)
assert before=={str(p):sha(p) for p in m.MAC.rglob('*') if p.is_file()}
report={'verdict':'CLEAR_RECORDED_PARTIAL_OBSERVATION_HOLD_EXCLUSIVE_READER_CLAIM','verified':counts,'counts':r['schemaCounts'],'windowsAdjunct':{'requested':20,'started':18,'eligible':15,'invalidHost':[3,16],'deadline':[18],'notStarted':[19,20]},'controls':{'readerValidJSONBaseline':'pass','readerValidJSONDrift':reader_fault,'duplicateCaptureID':rejected,'collectorOriginalBaseline':'20 byte-equivalent parsed envelopes','collectorRereadIDFault':{'status':changed['status'],'count':changed['count'],'original':caps[0]['id'],'changed':changed['captures'][0]['id'],'rejected':False}},'findings':[{'id':'workflow-rereads-outside-reader','severity':'scope-hold','proof':'workflow_collect ignores reader, loads capture.json through production load_artifact; schema-valid changed unique ID in in-memory reread accepted as collected20 after original reader verification. workflow_gate directly loads plan/cases/tuple/config/recipes/manifests & collection from disk. Thus source claim Only bytes returned by ArchiveByteReader enter parsing is false. No disk/raw mutation occurred.','required':'Describe production collector/gate disk reads honestly & bind consumed bytes to fixed expected pins, or supply verified bytes through these paths. Do not equate readerVerified20 with reader-bound workflow inputs.'},{'id':'fault-controls-partially-literal','severity':'coverage-hold','proof':'missing-origin-exact-code & windows-adjunct-not-capture are literal held assignments, not exercised guards. Producer tampered-reader appends invalid JSON; duplicate control accepts blocked-dependency as rejection. Independent actual reader validJSON drift & real comparator duplicate reason exercised here.'}], 'verifiedScope':['Actual original Mac20 envelopes & IDs match root gate captures exactly; schema collect20 & compare_case actual production execution available in venv','Historic Mac origin missing: originVerified0, parityQualified0, all recorded F10 reports blocked','F8 adapter executes pinned returned bytes in temporary module; mac_captures does not call adapter functions & no separate adapter semantic comparison asserted','Windows solely pinned peer facts, no typed Windows envelope admitted','F9/F10 real production dependencies pinned by root manifest & imported from repository; F10 recorded all-case replay remains blocked','Raw inputs unchanged'], 'originIssues':origin_issues,'importProvenance':provenance,'sourcePin':sha(P/'report.py'),'rootStagePin':sha(P/'root-replay-r1/stage-manifest.json'),'execution':'Offline venv Python actual readers/collector/comparator & temporary/in-memory faults only; no compiler/native/remote execution'}
(O/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps({'verdict':report['verdict'],'report':sha(O/'report.json'),'counts':counts,'duplicateReason':rejected['error'],'readerFault':reader_fault}))
