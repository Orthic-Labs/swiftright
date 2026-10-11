"""Bounded physical Clang declarations joined to thirteen ordinary Swift imports."""
import collections,datetime,gzip,hashlib,importlib.util,json,re
from pathlib import Path
from ast_reader import translation_nodes,located_nodes
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
PRODUCER=HERE.parent/'clang-external-process-v2'
SDK='/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk'
TARGET='arm64-apple-macosx27.0'
MANIFEST_HASH='sha256:4c07d91c986f552fdaa8f03734a47fa3b4d433de3402099975712d8c46972611'
# Frozen per-record namespace, spelling, C identity, physical definition & probe.
TARGETS=[
 ('AppKit.NSWindow','NSWindow','c:objc(cs)NSWindow','class',283,7),
 ('AppKit.NSApplication','NSApplication','c:objc(cs)NSApplication','class',194,8),
 ('AppKit.NSColor','NSColor','c:objc(cs)NSColor','class',77,9),
 ('AppKit.NSControl','NSControl','c:objc(cs)NSControl','class',19,10),
 ('AppKit.NSControl.ControlSize','NSControlSize','c:@E@NSControlSize','enum',91,11),
 ('AppKit.NSDirectionalEdgeInsets','NSDirectionalEdgeInsets','c:@S@NSDirectionalEdgeInsets','struct',53,12),
 ('AppKit.NSUnderlineStyle','NSUnderlineStyle','c:@E@NSUnderlineStyle','struct',61,13),
 ('AppKit.NSAnimationContext','NSAnimationContext','c:objc(cs)NSAnimationContext','class',19,14),
 ('Foundation.NSUserActivity','NSUserActivity','c:objc(cs)NSUserActivity','class',56,15),
 ('CoreFoundation.CGPoint','CGPoint','c:@S@CGPoint','struct',51,16),
 ('CoreFoundation.CGSize','CGSize','c:@S@CGSize','struct',59,17),
 ('CoreFoundation.CGRect','CGRect','c:@S@CGRect','struct',77,18),
 ('Spatial.Size3D','SPSize3D','c:@UA@SPSize3D','struct',112,19)]
def need(ok,why):
 if not ok:raise ValueError(why)
def digest(b):return 'sha256:'+hashlib.sha256(b).hexdigest()
def strict_json(raw):
 def pairs(rows):
  d={}
  for k,v in rows:need(k not in d,'duplicate JSON field');d[k]=v
  return d
 return json.loads(raw,object_pairs_hook=pairs)
# Use previously independently cleared raw-record parser, pinned byte-for-byte.
p=HERE.parent/'swift-stdlib-process-v2/exact_swift16.py'
need(digest(p.read_bytes())=='sha256:78620db51cdc47da5c1cafcb3f546cea918b67c8a3c5dcc5131b83988e652a0e','frozen raw parser')
s=importlib.util.spec_from_file_location('clang_bounded_raw',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
records=m.records

def physical(loc):
 return loc.get('spellingLoc',loc)
def position(loc,source,path):
 loc=physical(loc);need(loc.get('_physicalFile')==str(Path(path).resolve()) or (loc.get('_physicalFile') and str(Path(loc['_physicalFile']).resolve())==str(Path(path).resolve())),'AST physical header')
 offset=loc.get('offset');length=loc.get('tokLen');need(type(offset) is int and type(length) is int and 0<=offset<len(source) and length>0 and offset+length<=len(source),'AST location range')
 line=source[:offset].count(b'\n')+1;column=offset-source.rfind(b'\n',0,offset)
 need(('line' not in loc or loc['line']==line) and loc.get('col')==column,'AST actual line/column')
 return {'offset':offset,'line':line,'column':column,'token':source[offset:offset+length].decode()}
def walk(n):
 if isinstance(n,dict):
  yield n
  for v in n.values():yield from walk(v)
 elif isinstance(n,list):
  for v in n:yield from walk(v)
def complete(n):
 if n['kind']=='ObjCInterfaceDecl':return any(c.get('kind') in {'ObjCMethodDecl','ObjCPropertyDecl','ObjCIvarDecl'} for c in n.get('inner',[]))
 if n['kind']=='EnumDecl':return any(c.get('kind')=='EnumConstantDecl' for c in n.get('inner',[]))
 return n.get('completeDefinition') is True

def ast_identities(raw):
 selected=[]
 for n,a in located_nodes(translation_nodes(raw)):
  if n['kind'] in {'RecordDecl','EnumDecl','ObjCInterfaceDecl','TypedefDecl'}:selected.append((n,a))
 ids={}
 for n,a in selected:need(n['id'] not in ids,'duplicate AST declaration id');ids[n['id']]=(n,a)
 return selected,ids

def definition(target,selected,ids,source,path):
 q,name,usr,kind,line,probe_line=target
 k='ObjCInterfaceDecl' if kind=='class' else 'EnumDecl' if usr.startswith('c:@E@') else 'RecordDecl'
 expected_name='' if q=='Spatial.Size3D' else name
 candidates=[(n,a) for n,a in selected if n.get('name','')==expected_name and n['kind']==k and complete(n)]
 if q=='Spatial.Size3D':
  ts=[t for t,b in selected if t.get('name')==name and t['kind']=='TypedefDecl'];need(len(ts)==1,'AST anonymous typedef cardinality')
  ls=[x['decl']['id'] for x in walk(ts[0].get('inner',[])) if x.get('kind')=='RecordType' and isinstance(x.get('decl'),dict)];need(len(set(ls))==1,'AST anonymous typedef exact link')
  candidates=[(n,a) for n,a in candidates if n['id']==ls[0]]
 # Exactly one full definition, before physical-source filtering.
 need(len(candidates)==1,'AST definition cardinality '+q);n,a=candidates[0]
 need(not a,'AST physical top-level ancestry '+q)
 pos=position(n['loc'],source,path);need(pos['line']==line,'AST source definition line '+q)
 if q=='Spatial.Size3D':need(n.get('tagUsed')=='union' and pos['token']=='union','AST anonymous union definition')
 else:need(pos['token']==name,'AST definition token '+q)
 if kind=='class':
  begin=position(n['range']['begin'],source,path);end=position(n['range']['end'],source,path)
  need(source[begin['offset']:begin['offset']+10]==b'@interface' and source[end['offset']-1:end['offset']+3]==b'@end','AST complete Objective-C declaration '+q)
 else:
  need(usr.startswith('c:@E@') or n.get('tagUsed')==('union' if q=='Spatial.Size3D' else 'struct'),'AST nominal tag kind '+q)
 typedef=None
 if kind!='class':
  matches=[(t,b) for t,b in selected if t.get('name')==name and t['kind']=='TypedefDecl']
  need(len(matches)==1,'AST typedef cardinality '+q);typedef,b=matches[0];need(not b,'AST typedef ancestry '+q)
  tp=position(typedef['loc'],source,path);need(tp['token']==name,'AST typedef spelling '+q)
  links=[x['decl']['id'] for x in walk(typedef.get('inner',[])) if x.get('kind') in {'RecordType','EnumType'} and isinstance(x.get('decl'),dict)]
  need(len(set(links))==1,'AST typedef exact type link '+q)
  linked=ids.get(links[0]);need(linked is not None and linked[0]['kind']==k and linked[0].get('name','')==expected_name,'AST typedef linked declaration '+q)
  # Redeclarations form a bounded exact chain to complete declaration, or enum
  # forward declaration shares canonical previousDecl with actual definition.
  chain=[];cursor=linked[0]
  while True:
   need(cursor['id'] not in chain,'AST redeclaration cycle');chain.append(cursor['id'])
   if not cursor.get('previousDecl'):break
   need(cursor['previousDecl'] in ids,'AST missing previous declaration');cursor=ids[cursor['previousDecl']][0]
  nchain=[];cursor=n
  while True:
   need(cursor['id'] not in nchain,'AST definition redeclaration cycle');nchain.append(cursor['id'])
   if not cursor.get('previousDecl'):break
   need(cursor['previousDecl'] in ids,'AST definition missing previous declaration');cursor=ids[cursor['previousDecl']][0]
  need(set(chain)&set(nchain),'AST typedef/definition same redeclaration chain '+q)
  if q=='Spatial.Size3D':
   attrs=[x for x in typedef.get('inner',[]) if x['kind']=='SwiftNameAttr'];need(len(attrs)==1,'AST exact Swift name attribute')
   ap=position(attrs[0]['range']['begin']['expansionLoc'],source,path);need(ap['line']==131 and source[ap['offset']:].startswith(b'SPATIAL_SWIFT_NAME(Size3D)'),'AST Swift name source expansion')
 return {'definitionKind':k,'definitionPosition':pos,'physicalAncestorKinds':[x[0] for x in a],'typedefPosition':position(typedef['loc'],source,path) if typedef else None,'definition':n,'typedef':typedef}

def conditional_context(source,line):
 stack=[]
 for number,text in enumerate(source.decode().splitlines(),1):
  if number>line:break
  match=re.match(r'\s*#\s*(if|ifdef|ifndef|elif|else|endif)\b(.*)',text)
  if not match:continue
  op,expression=match.groups()
  if op in {'if','ifdef','ifndef'}:stack.append({'ifLine':number,'branchLine':number,'directive':op,'expression':expression.strip()})
  elif op in {'elif','else'}:need(stack,'source orphan conditional branch');stack[-1]={**stack[-1],'branchLine':number,'directive':op,'expression':expression.strip()}
  else:need(stack,'source orphan endif');stack.pop()
 return stack

def module_export(module,raw,umbrella,header):
 text=re.sub(r'/\*.*?\*/|//[^\n]*','',raw.decode(),flags=re.S)
 tokens=re.findall(r'"[^"\n]*"|[A-Za-z_][A-Za-z0-9_]*|[{}*\[\]!.]',text)
 prefix=['framework','module',module] if module!='Spatial' else ['module',module]
 need(tokens[:len(prefix)]==prefix,'module exact namespace '+module)
 need(tokens[len(prefix):len(prefix)+4]==['[','system',']','{'],'module top-level header '+module)
 depth=0;exports=[];umbrellas=[];excludes=[]
 for index,t in enumerate(tokens):
  if t=='{':depth+=1
  elif t=='}':
   depth-=1;need(depth>=0,'module unbalanced scope');need(depth!=0 or index==len(tokens)-1,'module extra top-level namespace')
  elif depth==1 and t=='export':exports.append(tokens[index+1])
  elif depth==1 and t=='umbrella':need(tokens[index+1]=='header','module umbrella kind');umbrellas.append(tokens[index+2].strip('"'))
  elif depth==1 and t=='exclude':need(tokens[index+1]=='header','module exclude kind');excludes.append(tokens[index+2].strip('"'))
 need(depth==0 and tokens[-1]=='}' and exports==['*'] and umbrellas==[module+'.h'],'module exact direct export/umbrella '+module)
 need(header.name not in excludes,'module target excluded '+module)
 includes=re.findall(r'^\s*#\s*(?:include|import)\s*<([^>]+)>\s*$',umbrella.decode(),re.M)
 need(includes.count(module+'/'+header.name)==1,'module unique umbrella public header edge '+module)
 return {'module':module,'umbrella':module+'.h','header':header.name,'directExport':'*','excludedHeaders':excludes}

class ExactClangOwners:
 def __init__(self):
  raw=(HERE/'capture-inputs.json').read_bytes();need(digest(raw)==MANIFEST_HASH,'frozen input manifest');self.manifest=strict_json(raw);self.paths={k:Path(v['path']) for k,v in self.manifest.items()};self.inputs={k:p.read_bytes() for k,p in self.paths.items()}
  for k,b in self.inputs.items():need(digest(b)==self.manifest[k]['sha256'] and len(b)==self.manifest[k]['bytes'],'actual immutable input '+k)
  self.original_processes=strict_json(self.inputs['processes']);self.expected_probe=self.inputs['probe'];self.expected_request=self.inputs['request']
  self.ast_cache={};self.ast_anchors={}
  initial=self.reconstruct()
  self.ast_anchors={r['target']:digest(json.dumps(r['ast'],sort_keys=True).encode()) for r in initial}
 def reconstruct(self,inputs=None):
  b=dict(self.inputs if inputs is None else inputs);need(set(b)==set(self.inputs),'exact input closure')
  # Semantics execute before final byte pins, so coforged bundle faults reach gates.
  need(b['probe']==self.expected_probe,'exact ordinary Swift probe tokens/modules')
  request=b['request'].decode();m.request_identity(request,self.paths['probe'])
  need(m.compilerargs(request)==[str(self.paths['probe']),'-sdk',SDK,'-target',TARGET],'SourceKit exact SDK/target/request')
  references=records(b['index'].decode());result=[]
  for t in TARGETS:
   q,name,usr,kind,line,probe_line=t;refname=q.split('.')[-1]
   text=b['probe'].decode().splitlines()[probe_line-1];column=text.index(refname,text.index('=')+1)+1
   at=[r for r in references if r['line']==probe_line and r['column']==column];need(len(at)==1,'ordinary import raw cardinality '+q)
   r=at[0];need(r['name']==refname and r['kind']=='source.lang.swift.ref.'+kind and r['usr']==usr and not r.get('is_implicit') and not r['parents'],'ordinary import exact name/kind/USR/owner '+q)
   module=q.split('.')[0];key='stdout:clang-'+module.lower()+'-ast';cachekey=digest(b[key])
   if cachekey not in self.ast_cache:self.ast_cache[cachekey]=ast_identities(b[key])
   selected,ids=self.ast_cache[cachekey];d=definition(t,selected,ids,b['source:'+q],self.paths['source:'+q])
   if self.ast_anchors:need(digest(json.dumps(d,sort_keys=True).encode())==self.ast_anchors[q],'AST full declaration/typedef/ancestry preimage '+q)
   export=module_export(module,b['map:'+module],b['umbrella:'+module],self.paths['source:'+q])
   # Own source/attributes/condition preimages are frozen independently of AST.
   need(b['source:'+q]==self.inputs['source:'+q],'physical full source/attributes/conditions '+q)
   result.append({'target':q,'physicalModule':module,'canonicalOwnerPath':q.split('.')[1:],'canonicalUsr':usr,'referenceKind':kind,'referenceLine':probe_line,'referenceColumn':column,'sourcePath':str(self.paths['source:'+q]),'sourceHash':digest(b['source:'+q]),'sourceText':b['source:'+q].decode().splitlines()[line-1],'sourceConditionFrames':conditional_context(b['source:'+q],line),'ast':d,'moduleExport':export,'supportOnly':q=='AppKit.NSControl'})
  # Reference closure includes modules & NSControl qualifier, all before dedup.
  original=records(self.inputs['index'].decode());observed=[tuple(r.get(k) for k in ['line','column','name','kind','usr']) for r in references if r['kind'].startswith('source.lang.swift.ref.')];expected=[tuple(r.get(k) for k in ['line','column','name','kind','usr']) for r in original if r['kind'].startswith('source.lang.swift.ref.')]
  need(collections.Counter(observed)==collections.Counter(expected),'ordinary import full reference closure')
  return result
 def validate(self,inputs=None):
  b=dict(self.inputs if inputs is None else inputs);result=self.reconstruct(b)
  proc=strict_json(b['processes']);need(set(proc)=={'schema','runs'} and proc['schema']=='clang-external-process-v2-runs','actual process schema')
  originals={r['name']:r for r in self.original_processes['runs']};need(len(proc['runs'])==7 and {r['name'] for r in proc['runs']}==set(originals),'actual process cardinality')
  for r in proc['runs']:
   name=r['name'];orig=originals[name]
   need(r['argv']==orig['argv'] and r['cwd']==str(ROOT),'actual process exact argv/cwd '+name)
   need(type(r['returncode']) is int and r['returncode']==0,'actual process returncode '+name)
   need(datetime.datetime.fromisoformat(r['startedAt'])<datetime.datetime.fromisoformat(r['endedAt']),'actual process timestamps '+name)
   need(r['toolIdentityPath']==str(self.paths['tool:'+name]) and r['toolIdentitySha256']==digest(b['tool:'+name]),'actual process tool binding '+name)
   for stream in ['stdout','stderr']:
    key=stream+':'+name;need(r[stream]==str(self.paths[key].relative_to(ROOT)) and r[stream+'Sha256']==digest(b[key]) and r[stream+'Bytes']==len(b[key]),'actual process stream binding '+name)
   stdout=b['stdout:'+name];raw=gzip.decompress(stdout) if name.startswith('clang-') else stdout
   need(r['rawStdoutSha256']==digest(raw) and r['rawStdoutBytes']==len(raw),'actual process lossless raw stdout '+name)
  for r in proc['runs']:
   if r['name'].startswith('clang-'):need(r['argv'].count('-target')==1 and r['argv'][r['argv'].index('-target')+1]==TARGET,'actual AST target missing/mismatch '+r['name'])
  for k,raw in b.items():need(digest(raw)==self.manifest[k]['sha256'],'final immutable input '+k)
  return [r for r in result if not r['supportOnly']]
