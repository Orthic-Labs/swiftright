"""Actual inferred global variable trees bind each physical C owner individually."""
import collections,datetime,json,re

def validate_nominals(g,b):
 from exact_clang import TARGETS,ROOT,SDK,TARGET,need,digest,strict_json,records,m
 paths=g.paths;probe=b['nominal:probe'].decode();source=paths['nominal:probe'];request=b['nominal:request'].decode()
 expected=g.inputs['probe'].decode().replace(': Any.Type','')
 need(probe==expected,'inferred exact ordinary probe modules/tokens')
 m.request_identity(request,source);need(m.compilerargs(request)==[str(source),'-sdk',SDK,'-target',TARGET],'inferred request exact SDK/target/source')
 refs=records(b['nominal:index'].decode());variables=[];roots=[];blocks=[];summaries={}
 for section in re.split(r'(?=Demangling for \$s)',b['nominal:trees'].decode()):
  if not section.strip():continue
  lines=section.splitlines();header=re.fullmatch(r'Demangling for (\$s\S+)',lines[0]);need(header is not None and len(lines)>2,'inferred tree section header')
  usr='s:'+header[1][2:];need(usr not in summaries,'inferred duplicate tree section');summaries[usr]=lines[-1];blocks.append('\n'.join(lines[:-1]+[header[1]+' ---> '+lines[-1]]))
 trees=m.TREE.trees('\n'.join(blocks));result={}
 def shape(n,kind,children):need(n['kind']==kind and n['text'] is None and n['index'] is None and len(n['children'])==children,'inferred exact tree '+kind);return n['children']
 def leaf(n,kind,text):need(n=={'kind':kind,'text':text,'index':None,'children':[]},'inferred exact leaf '+kind)
 for q,name,cusr,kind,line,pl in TARGETS:
  text=probe.splitlines()[pl-1];var=re.fullmatch(r'let (\w+) = (.*)\.self',text);need(var is not None,'inferred source binding')
  variable=var[1];refname=q.split('.')[-1];column=text.index(refname,text.index('=')+1)+1
  at=[r for r in refs if r['line']==pl and r['column']==column];need(len(at)==1,'inferred reference cardinality '+q)
  ref=at[0];need(ref['name']==refname and ref['kind']=='source.lang.swift.ref.'+kind and ref['usr']==cusr and not ref.get('is_implicit') and not ref['parents'],'inferred exact CUSR/name/kind '+q)
  at=[r for r in refs if r['line']==pl and r['column']==5];need(len(at)==1,'inferred variable cardinality '+q)
  decl=at[0];need(decl['name']==variable and decl['kind']=='source.lang.swift.decl.var.global' and not decl.get('is_implicit') and not decl['parents'],'inferred exact global variable '+q)
  original=[r for r in records(g.inputs['nominal:index'].decode()) if r['line']==pl and r['column']==5];need(len(original)==1 and decl['usr']==original[0]['usr'],'inferred variable exact actual USR')
  variables.append(decl['usr']);need(decl['usr'] in trees,'inferred actual variable tree missing')
  nodes=shape(trees[decl['usr']],'Global',1);children=shape(nodes[0],'Variable',3);leaf(children[0],'Module','owners');leaf(children[1],'Identifier',variable)
  nominal=shape(shape(shape(children[2],'Type',1)[0],'Metatype',1)[0],'Type',1)[0]
  nominalkind='Class' if kind=='class' else 'TypeAlias' if q=='Spatial.Size3D' else 'Structure'
  ns=shape(nominal,nominalkind,2);leaf(ns[0],'Module','__C');leaf(ns[1],'Identifier',name)
  need(summaries[decl['usr']]=='owners.'+variable+' : __C.'+name+'.Type','inferred tree human report binding')
  # Actual AST dump binds inferred variable, source position & metatype spelling.
  ast=b['nominal:ast'].decode();matches=re.findall(r'^\s*\(var_decl[^\n]*? range=\[([^\]]+)\] "'+re.escape(variable)+r'" interface_type="([^"]+)"',ast,re.M)
  need(len(matches)==1 and matches[0][0]==str(source)+':'+str(pl)+':5 - line:'+str(pl)+':5','inferred AST actual variable/source cardinality')
  need(matches[0][1]==g.nominal_ast_types[variable],'inferred AST exact metatype type')
  result[q]={'compiledNamespace':'__C','compiledPath':[name],'compiledKind':nominalkind,'nominalTree':nominal,'variableUSR':decl['usr'],'inferredVariable':variable,'inferredReferenceLine':pl,'inferredReferenceColumn':column,'inferredType':matches[0][1]}
 need(set(trees)==set(variables) and len(variables)==13,'inferred exact thirteen variable/tree closure')
 need(b['nominal:stdin'].decode()==''.join('$s'+usr[2:]+'\n' for usr in variables),'inferred actual demangle input closure/order')
 # Entire raw reference closure, including module tokens & ControlSize qualifier.
 baseline=records(g.inputs['nominal:index'].decode())
 signature=lambda rows:collections.Counter(tuple(r.get(k) for k in ['line','column','name','kind','usr']) for r in rows if r['kind'].startswith('source.lang.swift.ref.'))
 need(signature(refs)==signature(baseline),'inferred full reference closure')
 processes=strict_json(b['nominal:processes']);need(set(processes)=={'schema','runs'} and processes['schema']=='clang-nominal-import-v2-runs','inferred process schema')
 runs=processes['runs'];need(len(runs)==4 and {r['name'] for r in runs}=={'swift-typecheck','swift-ast-dump','sourcekit-index','swift-demangle-expand'},'inferred actual process cardinality')
 commands={'swift-typecheck':['xcrun','--sdk','macosx','swiftc','-typecheck','-sdk',SDK,'-target',TARGET,str(source)],'swift-ast-dump':['xcrun','--sdk','macosx','swiftc','-typecheck','-dump-ast','-sdk',SDK,'-target',TARGET,str(source)],'sourcekit-index':['xcrun','sourcekit-lsp','debug','run-sourcekitd-request','--request-file',str(paths['nominal:request'])],'swift-demangle-expand':[str(paths['tool:demangler']),'--expand']}
 toolkeys={'swift-typecheck':'tool:swift-typecheck','swift-ast-dump':'tool:swift-typecheck','sourcekit-index':'tool:sourcekit-index','swift-demangle-expand':'tool:demangler'}
 for run in runs:
  name=run['name'];need(run['argv']==commands[name] and run['cwd']==str(ROOT),'inferred actual process argv/cwd '+name)
  need(type(run['returncode']) is int and run['returncode']==0 and datetime.datetime.fromisoformat(run['startedAt'])<datetime.datetime.fromisoformat(run['endedAt']),'inferred actual process exit/time '+name)
  tool=toolkeys[name];need(run['toolIdentityPath']==str(paths[tool]) and run['toolIdentitySha256']==digest(b[tool]),'inferred actual process tool binding '+name)
  for stream in ['stdout','stderr']:
   key='nominal:'+stream+':'+name;need(run[stream]==str(paths[key].relative_to(ROOT)) and run[stream+'Sha256']==digest(b[key]) and run[stream+'Bytes']==len(b[key]),'inferred actual process stream '+name)
  inp='nominal:request' if name=='sourcekit-index' else 'nominal:probe';desc={'path':str(paths[inp].relative_to(ROOT)),'sha256':digest(b[inp]),'bytes':len(b[inp])};need(run['inputBindings']==[desc],'inferred exact process input bindings '+name)
  if name=='swift-demangle-expand':need(run['stdin']==str(paths['nominal:stdin'].relative_to(ROOT)) and run['stdinSha256']==digest(b['nominal:stdin']) and run['stdinBytes']==len(b['nominal:stdin']),'inferred actual demangle stdin')
 return result
