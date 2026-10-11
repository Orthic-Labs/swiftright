from pathlib import Path
import json,hashlib,importlib.util,inspect
from unittest.mock import patch
from factory.pipeline import workflow as w
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/pipeline/workflow-reader-repair-v2';O=P/'independent-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
s=json.loads((P/'stage-manifest.json').read_text())
for row in s['files']+[s['source']]:
 p=R/row['path']; assert sha(p)==row['sha256'].removeprefix('sha256:') and p.stat().st_size==row['bytes']
spec=importlib.util.spec_from_file_location('repair_v2_actual_controls',P/'test_reader_repair.py');t=importlib.util.module_from_spec(spec);spec.loader.exec_module(t)
original=w.generate_probe; generated=[]
def spy(recipe,case,out,**kw):
 root=kw['witness_root'];assert root.is_relative_to(R/'factory/.factory-work')
 for entry in recipe['witnesses']+recipe.get('negativeCases',[]):
  p=root/(entry['id']+'.swift');assert sha(p)==entry['sourceHash'].removeprefix('sha256:')
 generated.append({'case':case['id'],'witnessRoot':str(root)})
 return original(recipe,case,out,**kw)
with patch.object(w,'generate_probe',side_effect=spy): result=t.main()
assert result['prepareCaseDenominator']==len(generated)>0
assert 'artifact_reader' in inspect.signature(w.prepare).parameters
assert result['baselineCollected']==20 and result['mutationCollected']==19 and not result['gateEvidenceParityGranted']
report={'verdict':'CLEAR_BOUNDED_READER_CALLBACK_AND_GENERATOR_REPAIR','source':s['source'],'producerStageSha256':sha(P/'stage-manifest.json'),'actualControls':result,'temporaryWitnessProbeCount':len(generated),'verified':['prepare artifact_reader separate from OriginTrap callback; no origin callback consumed for artifacts','Actual generator consumes temporary copies whose full bytes equal recipe source pins','Returned capture ID & witness source drift reject exact hash mismatch before parse/generation','Legacy omitted-reader paths preserved; collect keyword reader explicitly retained'],'scope':'Source/Python generation & reader controls only; no compile/native/remote actions; per-read expected snapshot hashes require caller fixed input closure'}
(O/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(sha(O/'report.json'))
