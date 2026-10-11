#!/usr/bin/env python3
import copy,hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4];HERE=Path(__file__).resolve().parent;PACKET=HERE.parent
sys.path.insert(0,str(ROOT))
def pin(p):raw=p.read_bytes();return {'path':str(p.relative_to(ROOT)),'sha256':'sha256:'+hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
def main():
 from factory.gate.core import _check_recipe_profile_closure,baseline_case_refs
 from factory.recipes.cases import expand_cases
 from factory.recipes.recipes import load_recipes
 from factory.tools.canonical_json import sha256
 manifest=json.loads((PACKET/'stage-manifest.json').read_bytes())
 for e in manifest['entries']+manifest['trackedDependencies']:assert pin(ROOT/e['path'])==e,e['path']
 for name in ('core.py','test_gate.py'):
  original=subprocess.run(['git','show','HEAD:factory/gate/'+name],cwd=ROOT,capture_output=True,check=True).stdout
  assert original==(PACKET/'preimages'/name).read_bytes()
 candidate=ROOT/'factory/pipeline/tuple10-candidate/acceptance-candidate.json';before=candidate.read_bytes();config=json.loads(before);tuple_path=ROOT/'factory/pipeline/inputs/observed-tuple.json';tuple_value=json.loads(tuple_path.read_bytes());assert config['review']=='pending-maintainer-review'
 assert len(config['recipeRefs'])==len(config['baseline']['recipes'])==10
 trusted={r['id']:r for r in load_recipes()};config_refs={(r['id'],r['hash']) for r in config['recipeRefs']};profile_refs={(p['recipe']['id'],p['recipe']['hash']) for p in config['baseline']['recipes']};assert config_refs==profile_refs and len(config_refs)==10
 expansion_counts={}
 for p in config['baseline']['recipes']:
  recipe=trusted[p['recipe']['id']];assert p['recipe']['hash']==sha256(recipe);expanded=expand_cases(recipe,tuple_value,seed=p['seed'])['cases'];assert p['cases']==baseline_case_refs(expanded);expansion_counts[recipe['id']]=len(expanded)
 issues=[];_check_recipe_profile_closure(config,tuple_value,issues);assert issues==[]
 controls=[]
 def check(name,mutate,fragment):
  c=copy.deepcopy(config);mutate(c);issues=[];_check_recipe_profile_closure(c,tuple_value,issues);assert any(fragment in s for s in issues),(name,issues);assert c['review']=='pending-maintainer-review';controls.append({'name':name,'requiredReason':fragment,'issues':issues,'passed':True})
 check('ten-refs-one-profile',lambda c:c['baseline'].__setitem__('recipes',c['baseline']['recipes'][:1]),'membership differ')
 check('missing-ref',lambda c:c['recipeRefs'].pop(),'membership differ')
 check('extra-ref',lambda c:c['recipeRefs'].append({'id':'extra.recipe','hash':'sha256:'+'0'*64}),'membership differ')
 check('duplicate-ref',lambda c:c['recipeRefs'].append(copy.deepcopy(c['recipeRefs'][0])),'duplicate recipe profiles')
 check('duplicate-profile',lambda c:c['baseline']['recipes'].append(copy.deepcopy(c['baseline']['recipes'][0])),'duplicate recipe profiles')
 check('unselected-profile-omission',lambda c:c['baseline']['recipes'][-1].__setitem__('cases',[]),'complete trusted expansion')
 check('unselected-projection-hash',lambda c:c['baseline']['recipes'][-1]['cases'][0].__setitem__('projectionHash','sha256:'+'0'*64),'complete trusted expansion')
 check('unselected-duplicate-case',lambda c:c['baseline']['recipes'][-1]['cases'].append(copy.deepcopy(c['baseline']['recipes'][-1]['cases'][0])),'complete trusted expansion')
 check('profile-seed-bool',lambda c:c['baseline']['recipes'][-1].__setitem__('seed',True),'seed must be an integer')
 def wronghash(c):
  c['recipeRefs'][-1]['hash']='sha256:'+'0'*64;c['baseline']['recipes'][-1]['recipe']['hash']='sha256:'+'0'*64
 check('coherent-wrong-trusted-hash',wronghash,'recipe hash differs')
 def unknown(c):
  c['recipeRefs'][-1]['id']='unknown.recipe';c['baseline']['recipes'][-1]['recipe']['id']='unknown.recipe'
 check('coherent-unknown-id',unknown,'unknown trusted recipe')
 for typ,value in [('null',None),('bool',True),('int',1),('list',[]),('dict',{})]:
  check('config-hash-'+typ,lambda c,v=value:c['recipeRefs'][0].__setitem__('hash',v),'invalid recipe reference')
  check('profile-hash-'+typ,lambda c,v=value:c['baseline']['recipes'][0]['recipe'].__setitem__('hash',v),'invalid recipe reference')
 test=subprocess.run([sys.executable,'-m','unittest','factory.gate.test_gate'],cwd=ROOT,capture_output=True);assert test.returncode==0;assert b'OK' in test.stderr
 (HERE/'gate-tests.stdout').write_bytes(test.stdout);(HERE/'gate-tests.stderr').write_bytes(test.stderr)
 assert candidate.read_bytes()==before
 dependencies=[]
 for folder in ('factory/recipes','factory/spec/schema','factory/core','factory/tools'):
  for p in sorted((ROOT/folder).rglob('*')):
   if p.is_file() and '__pycache__' not in p.parts and (p.suffix in ('.py','.json','.swift')):dependencies.append(pin(p))
 report={'status':'CLEAR','scope':'F10 profile closure only; pending candidate remains pending; no native evidence or gatepass emitted','reviewer':pin(Path(__file__)),'ownerStage':pin(PACKET/'stage-manifest.json'),'core':pin(ROOT/'factory/gate/core.py'),'tests':pin(ROOT/'factory/gate/test_gate.py'),'candidate':pin(candidate),'projectionExpansionTuple':pin(tuple_path),'candidateReview':config['review'],'recipeRefs':10,'profiles':10,'completeExpansionCounts':expansion_counts,'controls':controls,'testProcess':{'argv':[sys.executable,'-m','unittest','factory.gate.test_gate'],'returncode':test.returncode,'stdout':pin(HERE/'gate-tests.stdout'),'stderr':pin(HERE/'gate-tests.stderr')},'dependencies':dependencies,'candidateBytesPreserved':True,'preimagesByteEqualHEAD':True}
 out=HERE/'profile-closure-review.json';out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(pin(out)))
if __name__=='__main__':main()
