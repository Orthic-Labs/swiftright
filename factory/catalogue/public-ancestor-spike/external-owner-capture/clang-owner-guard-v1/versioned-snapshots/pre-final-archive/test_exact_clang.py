"""Changed-byte controls use full genuine raw inputs through production guards."""
import copy,gzip,json,re
from exact_clang import *
from raw_faults import rewrite_ast
def run():
 g=ExactClangOwners();need(len(g.validate())==12,'accepted full eligibility baseline');base=g.reconstruct();need(len(base)==13,'accepted reconstruction baseline');controls=[]
 def fault(label,key,mutate,reason):
  need(len(g.validate())==12,'accepted full production control baseline')
  b=dict(g.inputs);changed=mutate(b[key]);need(changed!=g.inputs[key],'control bytes changed')
  for alias,path in g.paths.items():
   if path==g.paths[key]:b[alias]=changed
  try:g.validate(b)
  except ValueError as e:need(reason in str(e),'required semantic fault reason '+label+': '+str(e));controls.append({'label':label,'input':key,'rejection':str(e)})
  else:raise AssertionError('fault accepted '+label)
  if len(controls)%25==0:print('checked',len(controls),'semantic raw controls',flush=True)
 for q,name,usr,kind,line,pl in TARGETS:
  for field,old,new,reason in [('usr',usr,'c:other','ordinary import exact'),('name',q.split('.')[-1],'WrongName','ordinary import exact'),('kind','source.lang.swift.ref.'+kind,'source.lang.swift.ref.protocol','ordinary import exact')]:
   def mutate(raw,field=field,old=old,new=new,pl=pl):
    text=raw.decode();blocks=list(re.finditer(r'(?m)^\s*\{\n(?:.*\n)*?\s*\}',text))
    # Select genuine raw block by exact line & frozen USR; replace only that field.
    matches=[m for m in blocks if re.search(r'key.line: '+str(pl)+r',?\n',m[0]) and 'key.usr: '+json.dumps(usr) in m[0]]
    need(len(matches)==1,'control record selection');m=matches[0];block=m[0].replace('key.'+field+': '+json.dumps(old) if field!='kind' else 'key.kind: '+old,'key.'+field+': '+json.dumps(new) if field!='kind' else 'key.kind: '+new,1)
    return (text[:m.start()]+block+text[m.end():]).encode()
   fault(q+' wrong '+field,'index',mutate,reason)
  fault(q+' source condition','source:'+q,lambda b:b'\n#if 0\n'+b+b'\n#endif\n','AST actual line/column')
 for module in ['AppKit','Foundation','CoreFoundation','Spatial']:
  fault(module+' false namespace','map:'+module,lambda b:b.replace(('module '+module).encode(),b'module WrongModule',1),'module exact namespace')
  fault(module+' absent direct export','map:'+module,lambda b:b.replace(b'export *',b'export WrongModule'),'module exact direct export')
  q=next(r for r in TARGETS if r[0].startswith(module+'.'))
  header=g.paths['source:'+q[0]].name
  fault(module+' absent umbrella header','umbrella:'+module,lambda b:b.replace((module+'/'+header).encode(),(module+'/Wrong.h').encode()),'module unique umbrella')
 # Minimal coherent AST cannot replace full definitions, physical source & ancestry.
 for module in ['AppKit','Foundation','CoreFoundation','Spatial']:
  raw=gzip.compress(json.dumps({'id':'0x1','kind':'TranslationUnitDecl','loc':{},'range':{'begin':{},'end':{}},'inner':[]}).encode(),mtime=0)
  fault(module+' minimal raw AST','stdout:clang-'+module.lower()+'-ast',lambda b,raw=raw:raw,'AST anonymous typedef cardinality' if module=='Spatial' else 'AST definition cardinality')


 for content,label,reason in [(b'{"kind":"TranslationUnitDecl"}', 'missing AST header','AST root header missing/truncated'),(b'{"id":"1","kind":"TranslationUnitDecl","loc":{},"range":{"begin":{},"end":{}},"inner":[', 'truncated AST body','AST truncated'),(b'{"id":"1","kind":"TranslationUnitDecl","loc":{},"range":{"begin":{},"end":{}},"inner":[],"bogus":1}', 'extra AST root field','AST trailing data')]:
  fault(label,'stdout:clang-appkit-ast',lambda b,content=content:gzip.compress(content,mtime=0),reason)

 # Full actual AST controls, never producer's filtered JSON.
 for q,name,usr,kind,line,pl in TARGETS:
  module=q.split('.')[0];key='stdout:clang-'+module.lower()+'-ast'
  expectedkind='ObjCInterfaceDecl' if kind=='class' else 'EnumDecl' if usr.startswith('c:@E@') else 'RecordDecl'
  def select(n,name=name,expectedkind=expectedkind,q=q):
   if q=='Spatial.Size3D':return n.get('kind')=='TypedefDecl' and n.get('name')=='SPSize3D'
   return n.get('kind')==expectedkind and n.get('name')==name and complete(n)
  def forward(n):
   n.pop('completeDefinition',None);n['inner']=[];return [n]
  if q!='Spatial.Size3D':
   fault(q+' complete definition removed',key,lambda b,select=select:rewrite_ast(b,select,forward),'AST definition cardinality')
   def ancestry(n):return [{'id':'control-parent','kind':'FunctionDecl','name':'wrongOuter','loc':n['loc'],'range':n['range'],'inner':[n]}]
   fault(q+' function-owned declaration',key,lambda b,select=select:rewrite_ast(b,select,ancestry),'AST physical top-level ancestry')
   def wrongfile(n):
    loc=n['loc'].get('spellingLoc',n['loc']);loc['file']='/tmp/WrongHeader.h';return [n]
   fault(q+' forged physical location',key,lambda b,select=select:rewrite_ast(b,select,wrongfile),'AST physical header')
  if kind!='class':
   def tdselect(n,name=name):return n.get('kind')=='TypedefDecl' and n.get('name')==name
   def wronglink(n):
    for x in walk(n.get('inner',[])):
     if x.get('kind') in {'RecordType','EnumType'} and 'decl' in x:x['decl']['id']='missing-control-declaration'
    return [n]
   fault(q+' forged typedef link',key,lambda b,tdselect=tdselect:rewrite_ast(b,tdselect,wronglink),'AST definition cardinality' if q=='Spatial.Size3D' else 'AST typedef linked declaration')
  if q=='Spatial.Size3D':
   def dropattr(n):n['inner']=[x for x in n['inner'] if x['kind']!='SwiftNameAttr'];return [n]
   fault(q+' missing SwiftName attribute',key,lambda b,select=select:rewrite_ast(b,select,dropattr),'AST exact Swift name attribute')
 for q,name,usr,kind,line,pl in TARGETS:
  def duplicate(raw,pl=pl,usr=usr):
   text=raw.decode();blocks=list(re.finditer(r'(?m)^\s*\{\n(?:.*\n)*?\s*\}',text));matches=[m for m in blocks if re.search(r'key.line: '+str(pl)+r',?\n',m[0]) and 'key.usr: '+json.dumps(usr) in m[0]];need(len(matches)==1,'duplicate raw selector');x=matches[0];return (text[:x.end()]+',\n'+x[0]+text[x.end():]).encode()
  fault(q+' duplicate exact reference','index',duplicate,'ordinary import raw cardinality')

 # Actual inferred-type canonical root & raw-variable controls.
 for q,name,usr,kind,line,pl in TARGETS:
  variable=re.fullmatch(r'let (\w+) = .*',g.inputs['nominal:probe'].decode().splitlines()[pl-1])[1]
  def wrongtree(raw,variable=variable):
   sections=re.split(r'(?=Demangling for \$s)',raw.decode());hits=[i for i,x in enumerate(sections) if 'kind=Identifier, text="'+variable+'"' in x];need(len(hits)==1,'tree control selector');i=hits[0];sections[i]=sections[i].replace('kind=Module, text="__C"','kind=Module, text="WrongModule"',1);return ''.join(sections).encode()
  fault(q+' inferred wrong compiled namespace','nominal:trees',wrongtree,'inferred exact leaf Module')
  def wrongowner(raw,variable=variable,name=name):
   sections=re.split(r'(?=Demangling for \$s)',raw.decode());hits=[i for i,x in enumerate(sections) if 'kind=Identifier, text="'+variable+'"' in x];need(len(hits)==1,'tree owner selector');i=hits[0];sections[i]=sections[i].replace('kind=Identifier, text="'+name+'"','kind=Identifier, text="WrongNominal"',1);return ''.join(sections).encode()
  fault(q+' inferred wrong nominal','nominal:trees',wrongowner,'inferred exact leaf Identifier')
  def duplicate_tree(raw,variable=variable):
   sections=re.split(r'(?=Demangling for \$s)',raw.decode());hits=[x for x in sections if 'kind=Identifier, text="'+variable+'"' in x];need(len(hits)==1,'tree duplicate selector');return (raw.decode()+hits[0]).encode()
  fault(q+' inferred duplicate tree','nominal:trees',duplicate_tree,'inferred duplicate tree section')
 for key in ['request','nominal:request']:
  fault(key+' wrong target',key,lambda b:b.replace(TARGET.encode(),b'x86_64-apple-macosx27.0'),'request' if key=='nominal:request' else 'SourceKit exact')
 for key in ['probe','nominal:probe']:
  fault(key+' wrong qualified module',key,lambda b:b.replace(b'AppKit.NSWindow',b'Foundation.NSWindow',1),'ordinary' if key=='probe' else 'inferred exact ordinary')
 # Full eligibility baseline is intentionally held, while reconstruction accepts.
 # Receipt faults must change rejection from target hold to their own semantic gate.
 for run in g.original_processes['runs']:
  for field,value,reason in [('argv',['xcrun','clang'],'exact argv/cwd'),('cwd','/tmp/forged','exact argv/cwd'),('returncode',1,'returncode'),('stdoutSha256','sha256:'+'0'*64,'stream binding'),('stdoutBytes',0,'stream binding'),('toolIdentityPath','/tmp/clang','tool binding')]:
   if field=='stdoutBytes' and run[field]==0:continue
   b=dict(g.inputs);d=strict_json(b['processes']);matches=[r for r in d['runs'] if r['name']==run['name']];need(len(matches)==1,'receipt selector');matches[0][field]=value;b['processes']=json.dumps(d).encode();need(b['processes']!=g.inputs['processes'],'receipt bytes changed')
   try:g.validate(b)
   except ValueError as e:need(reason in str(e),'receipt semantic reason '+str(e));controls.append({'label':run['name']+' wrong '+field,'input':'processes','rejection':str(e),'baseline':'12 eligible; 13 reconstructed'})
   else:raise AssertionError('receipt fault accepted')
 hold=None
 return {'schema':'strict-clang-owner-controls-v1','reconstructionBaseline':13,'eligibleRequestedOwners':12,'hold':hold,'rawControls':controls}
if __name__=='__main__':
 d=run();(HERE/'controls.json').write_text(json.dumps(d,indent=2)+'\n');print(len(d['rawControls']),d['hold'])
