"""Changed-byte controls use full genuine raw inputs through production guards."""
import copy,gzip,json,re
from exact_clang import *
def run():
 g=ExactClangOwners();base=g.reconstruct();need(len(base)==13,'accepted reconstruction baseline');controls=[]
 def fault(label,key,mutate,reason):
  need(len(g.reconstruct())==13,'accepted reconstruction control baseline')
  b=dict(g.inputs);b[key]=mutate(b[key]);need(b[key]!=g.inputs[key],'control bytes changed')
  try:g.reconstruct(b)
  except ValueError as e:need(reason in str(e),'required semantic fault reason '+label+': '+str(e));controls.append({'label':label,'input':key,'rejection':str(e)})
  else:raise AssertionError('fault accepted '+label)
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

 # Full eligibility baseline is intentionally held, while reconstruction accepts.
 # Receipt faults must change rejection from target hold to their own semantic gate.
 for run in g.original_processes['runs']:
  for field,value,reason in [('argv',['xcrun','clang'],'exact argv/cwd'),('cwd','/tmp/forged','exact argv/cwd'),('returncode',1,'returncode'),('stdoutSha256','sha256:'+'0'*64,'stream binding'),('stdoutBytes',0,'stream binding'),('toolIdentityPath','/tmp/clang','tool binding')]:
   if field=='stdoutBytes' and run[field]==0:continue
   b=dict(g.inputs);d=strict_json(b['processes']);matches=[r for r in d['runs'] if r['name']==run['name']];need(len(matches)==1,'receipt selector');matches[0][field]=value;b['processes']=json.dumps(d).encode();need(b['processes']!=g.inputs['processes'],'receipt bytes changed')
   try:g.validate(b)
   except ValueError as e:need(reason in str(e),'receipt semantic reason '+str(e));controls.append({'label':run['name']+' wrong '+field,'input':'processes','rejection':str(e),'baseline':'13 reconstructed; full eligibility held by missing target'})
   else:raise AssertionError('receipt fault accepted')
 try:g.validate()
 except ValueError as e:need(str(e)=='actual AST target missing/mismatch clang-appkit-ast','exact target hold');hold=str(e)
 else:raise AssertionError('v2 missing target unexpectedly eligible')
 return {'schema':'strict-clang-owner-controls-v1','reconstructionBaseline':13,'eligibleRequestedOwners':0,'hold':hold,'rawControls':controls}
if __name__=='__main__':
 d=run();(HERE/'controls.json').write_text(json.dumps(d,indent=2)+'\n');print(len(d['rawControls']),d['hold'])
