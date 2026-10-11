import pathlib,sys,json,hashlib,gzip,re,importlib.util
from unittest.mock import patch
ROOT=pathlib.Path('/Volumes/D/claude/swiftright');HERE=ROOT/'factory/catalogue/public-ancestor-consumer/independent-review/clang-strict-v3';SOURCE=ROOT/'factory/catalogue/public-ancestor-spike/external-owner-capture/clang-owner-guard-v1';sys.path.insert(0,str(SOURCE))
from exact_clang import ExactClangOwners,TARGETS,digest,strict_json
from raw_faults import rewrite_ast
p=ROOT/'factory/catalogue/public-ancestor-spike/archive-resolver-v1/archive_resolver.py';s=importlib.util.spec_from_file_location('independent_archive',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
r1=m.ArchiveResolver();r2=m.ArchiveResolver(manifest_path=m.V2_MANIFEST_PATH,expected_manifest_sha256=m.V2_MANIFEST_SHA256);original=pathlib.Path.read_bytes;reads=[];cache={}
def blocked(path):
 if not str(path).startswith(str(ROOT)+'/'):raise AssertionError('live external read '+str(path))
 return original(path)
def reader(path,force_archive=False):
 assert force_archive is True;reads.append(path)
 if path not in cache:cache[path]=original(pathlib.Path(path)) if path.startswith(str(ROOT)+'/') else (r1 if path in r1._records else r2).read_bytes(path,force_archive=True)
 return cache[path]
with patch.object(pathlib.Path,'read_bytes',blocked):
 g=ExactClangOwners(read_bytes=reader,force_archive=True);rows=g.validate();assert len(rows)==12 and len(g.supportRows)==1
results=[]
def fault(label,overrides,reason):
 try:g.validate_overrides(overrides)
 except ValueError as e:
  assert reason in str(e),(label,str(e));results.append({'label':label,'rejected':True,'reason':str(e),'overrides':{k:{'sha256':digest(v),'bytes':len(v)} for k,v in overrides.items()}})
 else:raise AssertionError('fault admitted '+label)
def rawblock(text):
 blocks=list(re.finditer(r'(?m)^\s*\{\n(?:.*\n)*?\s*\}',text));hits=[x for x in blocks if re.search(r'key.line: 7,?\n',x[0]) and 'key.usr: "c:objc(cs)NSWindow"' in x[0]];assert len(hits)==1;return hits[0]
text=g.inputs['index'].decode();block=rawblock(text)
fault('known different canonical CUSR',{'index':(text[:block.start()]+block[0].replace('c:objc(cs)NSWindow','c:objc(cs)NSApplication')+text[block.end():]).encode()},'ordinary import exact')
fault('missing requested target',{'index':(text[:block.start()]+text[block.end():]).encode()},'ordinary import raw cardinality')
fault('duplicate requested target',{'index':(text[:block.end()]+',\n'+block[0]+text[block.end():]).encode()},'ordinary import raw cardinality')
proc=strict_json(g.inputs['processes']);run=next(x for x in proc['runs'] if x['name']=='clang-foundation-ast');run['argv'][run['argv'].index('-target')+1]='x86_64-apple-macosx27.0';fault('known different AST target',{'processes':json.dumps(proc).encode()},'actual process exact argv/cwd')
fault('missing AppKit public export',{'map:AppKit':g.inputs['map:AppKit'].replace(b'export *',b'export WrongModule',1)},'module exact direct export')
# Full Foundation stream retained; actual definition nested under forged function.
select=lambda n:n.get('kind')=='ObjCInterfaceDecl' and n.get('name')=='NSUserActivity' and any(c.get('kind') in {'ObjCMethodDecl','ObjCPropertyDecl','ObjCIvarDecl'} for c in n.get('inner',[]))
def nest(n):return [{'id':'independent-parent','kind':'FunctionDecl','name':'wrongOuter','loc':n['loc'],'range':n['range'],'inner':[n]}]
changed=rewrite_ast(g.inputs['stdout:clang-foundation-ast'],select,nest);proc=strict_json(g.inputs['processes']);run=next(x for x in proc['runs'] if x['name']=='clang-foundation-ast');raw=gzip.decompress(changed);run.update(stdoutSha256=digest(changed),stdoutBytes=len(changed),rawStdoutSha256=digest(raw),rawStdoutBytes=len(raw));fault('coherently rebound full AST nested declaration',{'stdout:clang-foundation-ast':changed,'processes':json.dumps(proc).encode()},'AST physical top-level ancestry')
trees=g.inputs['nominal:trees'].replace(b'kind=Module, text="__C"',b'kind=Module, text="WrongModule"',1).replace(b'__C.NSWindow.Type',b'WrongModule.NSWindow.Type',1);proc=strict_json(g.inputs['nominal:processes']);run=next(x for x in proc['runs'] if x['name']=='swift-demangle-expand');run.update(stdoutSha256=digest(trees),stdoutBytes=len(trees));fault('coherently rebound canonical tree namespace',{'nominal:trees':trees,'nominal:processes':json.dumps(proc).encode()},'inferred exact leaf Module')
fault('small missing-root-header EOF',{'stdout:clang-appkit-ast':gzip.compress(b'{"kind":"TranslationUnitDecl"}',mtime=0)},'AST root header missing/truncated')
fault('physical source identity shifted',{'source:CoreFoundation.CGPoint':b'\n'+g.inputs['source:CoreFoundation.CGPoint']},'AST actual line/column')
assert g.validate()==rows
result={'baseline':{'requested':12,'support':1,'archiveReads':len(reads),'uniquePaths':len(set(reads)),'liveExternalReads':0,'deterministicReplay':True},'controls':results,'requestedOwners':rows,'supportOwners':g.supportRows}
(HERE/'independent-replay.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({'baseline':result['baseline'],'controls':[{'label':r['label'],'reason':r['reason']} for r in results]}))
