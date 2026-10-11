from pathlib import Path
import importlib.util,sys,json,copy
HERE=Path(__file__).resolve().parent;BASE=HERE.parents[1];sys.path.insert(0,str(HERE.parents[4]))
s=importlib.util.spec_from_file_location('consumer_fixture_tests',BASE/'test_consumer.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
positive,usrs=m.parent_api_exclusion_fixture();test=m.CatalogueMergeTests();result=test.merge(positive,usrs)
assert len(result['symbols'])==len(m.BASE['symbols'])+1
faults=[]
mutations={'nominal_tree_is_entire_variable':lambda c:c['nonpublicOwnerEvidence'][0].update(nominalTree=c['tree']['children'][0]),'boolean_parent_cardinality':lambda c:c.update(parentRawCardinality=True),'foreign_scope_condition':lambda c:c['nonpublicOwnerEvidence'][0]['sourceScope'].update(conditions=['#if NEVER']), 'duplicate_owner_witness':lambda c:c['nonpublicOwnerEvidence'].append(copy.deepcopy(c['nonpublicOwnerEvidence'][0]))}
for label,mutate in mutations.items():
 r,usrs=m.parent_api_exclusion_fixture();mutate(r['compilerInventory'][-1]['childEvidence'])
 try:test.merge(r,usrs)
 except m.ConsumerError as e:faults.append({'fault':label,'accepted':False,'reason':str(e)})
 else:faults.append({'fault':label,'accepted':True})
(HERE/'initial-fault-result.json').write_text(json.dumps({'positiveNotPromoted':True,'faults':faults},indent=2)+'\n');print(json.dumps(faults))
