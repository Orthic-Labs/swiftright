from pathlib import Path
import sys,importlib.util,json,hashlib
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[4];sys.path.insert(0,str(ROOT))
s=importlib.util.spec_from_file_location('frozen_507_actual',HERE/'repaired-507-snapshot/consumer.py');c=importlib.util.module_from_spec(s);s.loader.exec_module(c)
p=ROOT/'factory/catalogue/public-ancestor-spike/public-ancestor-evidence-v2.json';raw=p.read_bytes();x=json.loads(raw);r=x['resolution'];source={tuple(a['key']):a for a in r['rows']};rows=[]
for record in r['compilerInventory']:
 child=record.get('childEvidence')
 if child and child.get('status')=='excluded-nonpublic-parent-api':
  parent=source[tuple(child['parentSourceKey'])]
  try:c._validate_nonpublic_parent_api(record,child,parent,r['rows'],r['compilerInventory'])
  except c.ConsumerError as error:outcome={'accepted':False,'reason':str(error)}
  else:outcome={'accepted':True}
  rows.append({'outcome':outcome,'record':record,'parent':parent,'sourceOwners':[source[(record['module'],parent['key'][1],w['sourceScope']['line'],w['sourceScope']['name'])] for w in child['nonpublicOwnerEvidence']]})
assert len(rows)==5
(HERE/'actual-five-preview-inputs.json').write_text(json.dumps({'scope':'preliminary actual5 parent API branch only; artifact not final-cleared','inputPath':str(p.relative_to(ROOT)),'inputSha256':hashlib.sha256(raw).hexdigest(),'sourceSha256':'507bf20dcf05b0d3372e39a260ea30e684e78d5f32700a5d87d1f9292c1923b4','rows':rows},indent=2)+'\n');print([e['outcome'] for e in rows])
