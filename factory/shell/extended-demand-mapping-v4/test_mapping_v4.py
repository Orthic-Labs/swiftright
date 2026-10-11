import copy,json,pathlib,importlib.util,hashlib
import generate as g
result,sdk=g.main()
assert len(result['rows'])==107 and result['componentCounts']=={'demandsWithComponents':8,'components':9,'observedNominalComponents':2,'proposedComponents':7,'newFullDemandResolutions':0,'registryMappedRows':0}
old=g.load(g.ROOT/'factory/shell/extended-demand-mapping-v3/mapping-v3.json')
for a,b in zip(old['rows'],result['rows']):assert all(b[k]==v for k,v in a.items()) and b['v4Evidence']['fullDemandResolved'] is False
p=g.ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py';sp=importlib.util.spec_from_file_location('controls_parser',p);m=importlib.util.module_from_spec(sp);sp.loader.exec_module(m)
records,source,sm,im=sdk['SwiftUI'];r=next(r for r in records if r['usr']==g.USRS['Button']);line=source.splitlines()[r['line']-1]
fields=['kind','name','usr','line','column','effective_access']
def serialize(r):
 return '{\n'+''.join('  key.'+k+': '+(json.dumps(r[k]) if k in ['name','usr'] else str(r[k]))+',\n' for k in fields)+'}\n'
raw=serialize(r);g.sdk_binding(m.entities(raw),source,'Button');receipts=[]
def denied(label,b,s=source):
 assert b!=raw or s!=source
 try:g.sdk_binding(m.entities(b),s,'Button')
 except ValueError as e:receipts.append({'control':label,'changedActualBytes':True,'acceptedBaseline':True,'rejected':True,'reason':str(e),'rawSha256':hashlib.sha256(b.encode()).hexdigest(),'sourceSha256':hashlib.sha256(s.encode()).hexdigest()})
 else:raise AssertionError(label)
for field,val in [('usr','s:7SwiftUI5AlertV6ButtonV'),('name','WrongButton'),('kind','source.lang.swift.decl.enum'),('line',r['line']+1),('column',r['column']+1),('effective_access','source.decl.effective_access.internal')]:
 x=copy.deepcopy(r);x[field]=val;denied('raw-'+field,serialize(x))
denied('raw-duplicate',raw+raw)
denied('raw-owner-context','{\n  key.kind: source.lang.swift.decl.struct,\n  key.name: "WrongOwner",\n  key.usr: "s:7SwiftUI10WrongOwnerV",\n  key.line: 1,\n'+''.join('  '+x+'\n' for x in raw.splitlines())+'}\n')
denied('source-access',raw,source.replace(line,line.replace('public struct','internal struct'),1))
denied('source-owner-name',raw,source.replace(line,line.replace('struct Button','struct WrongButton'),1))
assert len(receipts)==10
out=g.OUT/'evidence/controls.json';out.write_text(json.dumps({'kind':'v4-sdk-source-semantic-controls','controls':receipts,'passed':10,'baselineComponents':9,'productionCallable':'generate.sdk_binding'},indent=2)+'\n')
print('10/10 changed raw/source semantic controls passed;107 rows preserved;9 components bound.')
