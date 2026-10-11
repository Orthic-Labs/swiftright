"""Real recipe/probe validators, tuple-free candidate projections & fault controls."""
from pathlib import Path
import copy,hashlib,json
from factory.core.artifacts import validate_artifact,file_hash
from factory.recipes.cases import _planned_cases
from factory.probes.generator import _validate,_specialize_witness,_witness,_negative_witness,ProbeError
ROOT=Path(__file__).resolve().parent

def validate(recipe):
 validate_artifact(recipe);_validate(recipe,'recipe')
 if recipe['provenance']['review']['decision']!='candidate':raise ValueError('Candidate decision required')
 if not all(a['observability']=='blocked' for a in recipe['assertions']):raise ValueError('Blocked observability required')
 witness=recipe['witnesses'][0]
 raw=(ROOT/'witnesses'/f"{witness['id']}.swift").read_bytes()
 h='sha256:'+hashlib.sha256(raw).hexdigest()
 if witness['sourceHash']!=h or witness['resources']!=[{'id':witness['id']+'.swift','hash':h}]:raise ValueError('Witness source binding drift')
 descriptors=[]
 for row in _planned_cases(recipe,0):
  projection=row.descriptor()  # No case artifact or measured tuple invented.
  if row.case_id in {n['id'] for n in recipe['negativeCases']}:
   n=next(n for n in recipe['negativeCases'] if n['id']==row.case_id)
   _,source=_negative_witness(n,ROOT/'witnesses')
  else: source=_specialize_witness(recipe,{'id':row.case_id,'inputs':row.inputs},raw)
  projection.update({'projectedWitnessHash':'sha256:'+hashlib.sha256(source).hexdigest(),'executionEligible':False,'projectionOnly':True})
  descriptors.append(projection)
 try:_witness(recipe,ROOT/'witnesses')
 except ProbeError as e:
  if 'unsupported block' not in str(e):raise
  generator=str(e)
 else: raise ValueError('Unexpected production generator support; review required')
 return {'block':recipe['block'],'recipeHash':file_hash(ROOT/'data'/f"{recipe['block']}.json"),'witnessHash':h,'descriptors':descriptors,'generatorHold':generator,'measurementTuple':None,'compilerRuns':0,'nativeRuns':0}

def validate_join(join):
 raw=(ROOT/'dependencies/registry-candidate-manifest.json').read_bytes()
 candidate=json.loads(raw)
 expected_hash='sha256:'+hashlib.sha256(raw).hexdigest()
 if join['candidateManifest']['hash']!=expected_hash:raise ValueError('Candidate raw binding drift')
 indices={'swiftui.popover':[0],'swiftui.animation.spring-interruption':[0,1],'swiftui.text-field-ime':[0],'swiftui.environment-font-color-scheme':[0,1,2],'swiftui.context-menu':[0]}
 rows=join['rows']
 if len(rows)!=5 or {r['block'] for r in rows}!=set(indices):raise ValueError('Source join membership drift')
 for row in rows:
  block=next(b for b in candidate['blocks'] if b['id']==row['block'])
  recipe=json.loads((ROOT/'data'/f"{row['block']}.json").read_bytes())
  if row['recipeHash']!=file_hash(ROOT/'data'/f"{row['block']}.json") or row['witnessHash']!=recipe['witnesses'][0]['sourceHash']:raise ValueError('Recipe/source join drift')
  if recipe['provenance']['inputs']!=[{'id':candidate['id'],'hash':expected_hash}]:raise ValueError('Consumed candidate raw binding drift')
  if row['selectedSourceSymbols']!=[block['symbols'][i] for i in indices[row['block']]]:raise ValueError('Exact USR source join drift')
  if row['semanticDependencies']!=[] or row['registryPromotion'] is not False or row['nativeQualification'] is not False:raise ValueError('Unproven source promotion')

def main():
 rows=[];controls=[]
 for p in sorted((ROOT/'data').glob('*.json')):
  r=json.loads(p.read_bytes());rows.append(validate(r))
  for name,mutation in [('source-drift',lambda x:x['witnesses'][0].update(sourceHash='sha256:'+'0'*64)),('negative-source-drift',lambda x:x['negativeCases'][0].update(sourceHash='sha256:'+'0'*64)),('promoted-observability',lambda x:x['assertions'][0].update(observability='available')),('duplicate-axis',lambda x:x['axes'].extend([{'id':'fault','values':[1]},{'id':'fault','values':[2]}])),('undeclared-input',lambda x:None)]:
   bad=copy.deepcopy(r)
   try:
    if name=='undeclared-input':_specialize_witness(bad,{'id':'candidate','inputs':{'undeclared':'x'}},(ROOT/'witnesses'/f"{bad['witnesses'][0]['id']}.swift").read_bytes())
    else:mutation(bad);validate(bad)
   except (ValueError,AssertionError):controls.append({'block':r['block'],'fault':name,'rejected':True,'syntheticMutation':True})
   else:raise AssertionError('Fault accepted: '+name)
 join=json.loads((ROOT/'registry-source-join.json').read_bytes());validate_join(join)
 for name,mutate in [('usr-misbinding',lambda j:j['rows'][0]['selectedSourceSymbols'][0].update(selector='usr:synthetic-wrong')),('duplicate-block',lambda j:j['rows'].__setitem__(1,copy.deepcopy(j['rows'][0]))),('stale-recipe',lambda j:j['rows'][0].update(recipeHash='sha256:'+'0'*64))]:
  bad=copy.deepcopy(join);mutate(bad)
  try:validate_join(bad)
  except ValueError:controls.append({'fault':name,'rejected':True,'syntheticMutation':True})
  else:raise AssertionError('Join fault accepted: '+name)
 result={'kind':'round2-candidate-source-projection-controls-v1','scope':'source-only, no typecheck/native capability qualification','recipes':rows,'faultControls':controls,'compilerRuns':0,'nativeRuns':0,'measurementTuple':None}
 (ROOT/'validation.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps({'recipes':len(rows),'projections':sum(len(r['descriptors']) for r in rows),'faults':len(controls),'nativeRuns':0}))
if __name__=='__main__':main()
