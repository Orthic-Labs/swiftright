import sys,json,hashlib,copy,importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[4];sys.path.insert(0,str(ROOT))
s=importlib.util.spec_from_file_location('frozen66',HERE/'repaired-66-snapshot/consumer.py');c=importlib.util.module_from_spec(s);s.loader.exec_module(c)
p=ROOT/'factory/catalogue/public-ancestor-spike/public-ancestor-evidence-v2.json';raw=p.read_bytes();r=json.loads(raw)['resolution'];source={tuple(a['key']):a for a in r['rows']};rows=[];faults=[]
for record in r['compilerInventory']:
 child=record.get('childEvidence')
 if not child or child.get('status')!='excluded-nonpublic-parent-api':continue
 parent=source[tuple(child['parentSourceKey'])];c._validate_nonpublic_parent_api(record,child,parent,r['rows'],r['compilerInventory']);rows.append({'module':record['module'],'line':record['line'],'usr':record['usr'],'rawAccess':record['effectiveAccess'],'typedAccess':child['typedAST']['access'],'conditions':child['conditions'],'effectivePublic':child['effectivePublic']})
 mutations={'ast_access':lambda x:x['typedAST'].update(access='private'),'ast_kind':lambda x:x['typedAST'].update(kind='func_decl'),'ast_family':lambda x:x['typedAST'].update(family='set'),'ast_line':lambda x:x['typedAST'].update(line=x['typedAST']['line']+1),'ast_property':lambda x:x['typedAST'].update(propertyName='wrong'),'bool_cardinality':lambda x:x.update(parentRawCardinality=True),'duplicate_witness':lambda x:x['nonpublicOwnerEvidence'].append(copy.deepcopy(x['nonpublicOwnerEvidence'][0])),'foreign_conditions':lambda x:x['nonpublicOwnerEvidence'][0]['sourceScope'].update(conditions=[{'ifLine':99999}]),'nominal_leaf_extra':lambda x:x['nonpublicOwnerEvidence'][0]['nominalTree']['children'][0].update(children=[{'kind':'Function','children':[]}]),'nominal_wrong_name':lambda x:x['nonpublicOwnerEvidence'][0]['nominalTree']['children'][1].update(text='WrongNominal')}
 for label,mut in mutations.items():
  bad=copy.deepcopy(child);mut(bad)
  try:c._validate_nonpublic_parent_api(record,bad,parent,r['rows'],r['compilerInventory'])
  except c.ConsumerError as e:faults.append({'line':record['line'],'fault':label,'reason':str(e)})
  else:raise AssertionError((record['line'],label))
 # AST declared-parent duplication must fail independently of nominal witness data.
 bad=copy.deepcopy(child);ast_parent=next(a for a in bad['typedAST']['owners'] if a['kind']=='var_decl');bad['typedAST']['owners'].append(copy.deepcopy(ast_parent))
 try:c._validate_nonpublic_parent_api(record,bad,parent,r['rows'],r['compilerInventory'])
 except c.ConsumerError as e:faults.append({'line':record['line'],'fault':'duplicate_AST_property_parent','reason':str(e)})
 else:raise AssertionError('AST parent duplication')
 badrec=copy.deepcopy(record);badrec['effectiveAccess']='source.decl.effective_access.internal'
 try:c._validate_nonpublic_parent_api(badrec,child,parent,r['rows'],r['compilerInventory'])
 except c.ConsumerError as e:faults.append({'line':record['line'],'fault':'contradictory_explicit_raw_access','reason':str(e)})
 else:raise AssertionError('explicit raw contradiction')
assert len(rows)==5 and len(faults)==60
report={'scope':'preliminary consumer parent API exclusion source review only; full pinned proof/candidate next','sourceSha256':'66c6d03275a2da2898de6862c6d494703116c0e04094f186e4770cc21966a30b','testsSha256':'47758ea781e86290f26df1b0c11241066720198c377088823225f7e59246c943','actualProofInputSha256':hashlib.sha256(raw).hexdigest(),'rows':rows,'faults':faults,'candidateEmitted':False};(HERE/'final-branch-replay-result.json').write_text(json.dumps(report,indent=2)+'\n');print(len(rows),len(faults))
