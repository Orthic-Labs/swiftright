import ast,hashlib,importlib.util,json,sys,unittest
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
BASE=HERE.parent/'destructor-api-eligibility-proof/archive-wrapper-v2'
def digest(raw):return hashlib.sha256(raw).hexdigest()
def load(path,name):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);sys.modules[name]=m;s.loader.exec_module(m);return m
pins={'archive_wrapper.py':'77259710191f358cd9add04a1350ec5b98821d7bbe3337e7a26a7b84b4fe4970','evaluate_reader.py':'0d5a8f1237c1c547890723c4272b7b06dc249d0b46f383e2d23c12743c9fe80d','test_archive_wrapper.py':'567ffa718a59e89051c0490bb420f39d979d1c8e2ee023d57f4329f548cf8bb9'}
snapshot=HERE/'reviewed-v2';snapshot.mkdir(exist_ok=True)
for name,h in pins.items():raw=(BASE/name).read_bytes();assert digest(raw)==h;(snapshot/name).write_bytes(raw)
original=(BASE.parent/'prove_access.py').read_text();adapted=(BASE/'evaluate_reader.py').read_text();old="Path(fields['filepath']).resolve()==src.resolve()";new='cursor_source_identity(fields,src)'
def function(text):return next(n for n in ast.parse(text).body if isinstance(n,ast.FunctionDef) and n.name=='evaluate')
assert ast.dump(function(original.replace(old,new)),include_attributes=False)==ast.dump(function(adapted),include_attributes=False)
w=load(BASE/'archive_wrapper.py','independent_wrapper_v2');actions=[]
methods={name:getattr(Path,name) for name in ('open','stat','resolve')}
def protected(name):
 def call(path,*a,**kw):
  if str(path).startswith(('/Applications/','/Users/')):actions.append({'method':name,'path':str(path)});raise AssertionError('original external access')
  return methods[name](path,*a,**kw)
 return call
with patch.object(Path,'open',protected('open')),patch.object(Path,'stat',protected('stat')),patch.object(Path,'resolve',protected('resolve')):
 replay=w.Replay(force_archive=True);before=dict(replay.original.evaluate.__globals__);out=replay.verify_all();assert before==replay.original.evaluate.__globals__
 encoded=(json.dumps(out,indent=2)+'\n').encode();assert digest(encoded)==w.EVIDENCE_HASH
 for module in ('SwiftUI','SwiftUICore'):
  raw=w.ast_bytes(module,force_archive=True);assert digest(raw)==replay.bindings[str(replay.original.RAW/(module+'-arm64.stdout'))]['sha256'][7:]
assert not actions
t=load(BASE/'test_archive_wrapper.py','independent_wrapper_controls');result=unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromModule(t));assert result.wasSuccessful()
report={'status':'independent-v2-archive-wrapper-cleared','sourcePins':pins,'rows':len(out['rows']),'reconstructedArtifactSha256':digest(encoded),'verifiedOriginalExternalAccesses':actions,'soleEvaluateASTDelta':new,'originalEvaluateGlobalsUnchanged':True,'controlsRun':result.testsRun,'completeRawArchiveMembers':len(replay.raw_rows),'semanticInputBindings':len(replay.bindings),'scope':'exact42 physical declaration effective access only; canonical ABI identity/API eligibility remains separate','noCompilerExecution':True}
(HERE/'independent-v2-clearance.json').write_text(json.dumps(report,indent=2)+'\n');print(digest((HERE/'independent-v2-clearance.json').read_bytes()))
