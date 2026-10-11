from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
import importlib.util,json,hashlib
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/pipeline/paired-padding-settled-v3';O=P/'independent-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
spec=importlib.util.spec_from_file_location('paired_padding_review',P/'report.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def walk(n):
 yield n
 for c in n.get('children',[]):yield from walk(c)
f8=SimpleNamespace(_walk=walk)
c=m.load_config(m.reader_for_repo());baseline,counts=m.windows_rows(c,f8)
original=Path.read_bytes
changed=[]
def forged_read(p):
 raw=original(p)
 if p.name=='native.uia.json' and str(p).startswith(str(m.WIN_ROOT)):
  d=json.loads(raw.decode('utf-8-sig'))
  for n in walk(d):
   if n.get('controlType')=='ControlType.Text':n['name']='FORGED_NO_IMMUTABLE_HASH'
  changed.append(str(p.relative_to(R)));return json.dumps(d).encode()
 return raw
with patch.object(Path,'read_bytes',forged_read):forged,newcounts=m.windows_rows(c,f8)
assert counts==newcounts and len(forged)==18
assert all(row['labels']==[{'role':'ControlType.Text','value':'FORGED_NO_IMMUTABLE_HASH'}] for row in forged if row['status']=='eligible')
assert baseline[0]['labels']!=forged[0]['labels']
source=(P/'report.py').read_text()
assert 'spec.loader.exec_module(module)' in source and 'read_repo(repo_reader, F8_PATH, F8_SHA256)' in source
assert 'recipe=recipe, cases=[], captures=[], tuple_value={}' in source and 'result["status"] = "blocked"' in source
assert '"layout": [{"text": "Box"}]' in source
assert 'out["promotion-mutation"] = "held-by-claims"' in source
report={'verdict':'HOLD_CONCRETE_PROVENANCE_AND_INTEGRATION_DEFECTS','findings':[{'id':'windows-unchecked-bytes','proof':'Actual production windows_rows accepted18 in-memory substituted UIA files, 15eligible labels FORGED_NO_IMMUTABLE_HASH with exact same counts; peer pin remained valid. Raw labels never checked against immutable peer input hashes. No disk evidence modified.','required':'Read each Windows rawfile through pinned byte reader/verified extraction anchored to immutable peer hashes before interpretation; preserve held origin separately.'},{'id':'f8-reopened-source','proof':'Verified ArchiveByteReader F8 raw discarded; exec_module reopens F8_PATH independently.','required':'Execute exact verified bytes or bind second consumed read; pin imported dependencies.'},{'id':'synthetic-f9-f10','proof':'F9 fabricates case/capture envelopes with hardcoded Box layout; F10 runs empty cases/captures/tuple then forcibly overrides status=blocked. Actual observed18/partial data never reaches gate acceptance path.','required':'Use truthful typed observational report inputs; distinguish render-only blocked dashboard from production acceptance exercise, route actual typed captures/proofs to gates without forged completion.'},{'id':'vacuous-dangerous-controls','proof':'promotion-mutation is literal held-by-claims; peer fault broadly treats any Exception as rejection; mac mutation writes immutable summary then restores bytes.','required':'Independent bounded fixture or reader-injection faults with exact rejection reasons; no original evidence mutation.'}], 'baselineCounts':counts,'faultResult':{'changedUIAFiles':len(set(changed)),'eligibleForgedLabels':15,'productionRejected':False},'claimsRetained':'20Mac/18started/15eligible/2invalid/1deadline/2unstarted, raw timing &geometry/pixel/native parity held; failure concerns provenance &integration claims, no parity promotion observed','reviewExecution':'Offline Python read mock only; no raw/source producer writes, compiler/native/remote execution','pins':{str(p.relative_to(R)):sha(p) for p in [P/'report.py',P/'report.json',P/'fault-controls.json',P/'stage-manifest.json']}}
(O/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(sha(O/'report.json'))
