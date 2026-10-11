#!/usr/bin/env python3
"""Exact sixteen physical Swift source/import correspondences; no module alias."""
import collections, functools, hashlib, importlib.util, json, re, shlex
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
BASE=ROOT/'factory/catalogue/public-ancestor-spike'
SCRATCH=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/swift-stdlib-process-v2')
SDK='/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk'
TARGET='arm64-apple-macosx27.0'
TOOLCHAIN=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain')
SOURCE=Path(SDK)/'usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface'
HEADER=BASE/'external-owner-header-index-v1/swift-foundation'
SOURCE_HASH='sha256:ccd1c05df90165f805e7de278ca3f6945f1a1544e9b8b3da0297ebfcc80f3669'
HEADER_RAW_HASH='sha256:12c4f19b2fb195ca92e748fb6e98bb961e521baba6035dc6da7bfefc7bebda63'
HEADER_REQUEST_HASH='sha256:5b0a6e9b82f16949b6e39b3b00ff6bbf281312adaf7c9788a2ae33e627b6e4c8'
HEADER_EVIDENCE_HASH='sha256:7f332345a044d54ec4617fa06c7bf73513235c08f4e7aa767446924a0842f3bb'
INPUT_MANIFEST_HASH='sha256:c760bc8bb37e7c02aaa6123f379293488d5ab3b840282d4c75e060486d456c09'
TOOLS={'compiler':(TOOLCHAIN/'usr/bin/swiftc','sha256:84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7'),'sourcekitLsp':(TOOLCHAIN/'usr/bin/sourcekit-lsp','sha256:557857429e47f330546941521a7a9b38410895a7308eac8eceb28056e6fe5396'),'sourcekitd':(TOOLCHAIN/'usr/lib/sourcekitd.framework/Versions/A/sourcekitd','sha256:d200bd40b3c44181d086c218d9925bacf2d54befa44031dedf15abb51830292b'),'demangler':(TOOLCHAIN/'usr/bin/swift-demangle','sha256:ae7da66c8a56fb3b90817c10eb816c82e25bf7a26ae0158effbda223f7f0fefe')}
TARGETS=[('Optional','enum',16948,'s:Sq'),('Never','enum',17607,'s:s5NeverO'),('Float','struct',39669,'s:Sf'),('Double','struct',40283,'s:Sd'),('Int','struct',45246,'s:Si'),('Int8','struct',41368,'s:s4Int8V'),('Int16','struct',42329,'s:s5Int16V'),('Int32','struct',43290,'s:s5Int32V'),('Int64','struct',44259,'s:s5Int64V'),('UInt','struct',44762,'s:Su'),('UInt8','struct',40905,'s:s5UInt8V'),('UInt16','struct',41864,'s:s6UInt16V'),('UInt32','struct',42825,'s:s6UInt32V'),('UInt64','struct',43787,'s:s6UInt64V'),('RangeReplaceableCollection','protocol',18661,'s:Sm'),('MutableCollection','protocol',15531,'s:SM')]
def require(ok,why):
    if not ok:raise ValueError(why)
def digest(b):return 'sha256:'+hashlib.sha256(b if isinstance(b,bytes) else b.encode()).hexdigest()
def load(name,p,expected):
    require(digest(p.read_bytes())==expected,'frozen parser bytes changed');s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
LEX=load('swift16_frozen_lexical',BASE/'lexical_model_v2.py','sha256:cc6d4dab563f713b91c0ef1f29cbb214a3c129c8f5f3823f438ac24aef75cdd6')
TREE=load('swift16_frozen_trees',ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py','sha256:83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5')
@functools.lru_cache(maxsize=8)
def records(raw):
    out=[];stack=[]
    for line in raw.splitlines():
        if m:=re.fullmatch(r'(\s*)\{',line):stack.append({'indent':len(m[1]),'fields':{}});continue
        if m:=re.fullmatch(r'(\s*)\},?',line):
            require(stack and stack[-1]['indent']==len(m[1]),'raw closing structure');r=stack.pop()['fields']
            if all(k in r for k in ['kind','name','usr','line','column']):r['parents']=[dict(p['fields']) for p in stack if p['fields'].get('kind','').startswith('source.lang.swift.decl.')];out.append(r)
            continue
        m=re.fullmatch(r'(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?),?',line)
        if m and stack and len(m[1])==stack[-1]['indent']+2:
            v=m[3].removesuffix(',');v=json.loads(v) if v.startswith('"') else int(v) if v.isdigit() else v;require(m[2] not in stack[-1]['fields'],'duplicate raw field');stack[-1]['fields'][m[2]]=v
    require(not stack,'unterminated raw structure');return out
@functools.lru_cache(maxsize=4)
def nominal_source(source):
    depth=0;branches=[];result={};attributes=[]
    for number,(original,code) in enumerate(zip(source.splitlines(),LEX.code_lines(source)),1):
        text=code.strip()
        if text.startswith('#if '):branches.append({'ifLine':number,'branchLine':number,'expression':text[4:]})
        elif text.startswith('#elseif ') or text=='#else':require(branches,'orphan source branch');branches[-1]={**branches[-1],'branchLine':number,'expression':text}
        elif text=='#endif':require(branches,'orphan source endif');branches.pop()
        f=LEX.fields(code)
        if depth==0 and f and f['kind'] in {'struct','enum','protocol'}:
            result.setdefault(f['name'],[]).append({'line':number,'column':original.index(f['name'])+1,'kind':f['kind'],'access':f['explicitAccess'],'text':original,'conditions':[dict(b) for b in branches],'attributes':list(attributes)})
        if original.strip().startswith('@') and f is None:attributes.append({'line':number,'text':original.strip()})
        elif original.strip() and not original.strip().startswith('//'):attributes=[]
        depth+=code.count('{')-code.count('}');require(depth>=0,'negative source brace depth')
    require(depth==0 and not branches,'unbalanced source scope');return result
def compilerargs(request):
    m=re.search(r'key.compilerargs:\s*\[(.*?)\]',request,re.S);require(m is not None,'missing compilerargs');return json.loads('['+m[1]+']')
def request_identity(request,path):
    require(re.findall(r'\bkey\.(\w+)\s*:',request)==['request','sourcefile','compilerargs'],'request field closure/cardinality')
    require(re.findall(r'key.request:\s*([^,\n]+)',request)==['source.request.indexsource'],'request kind/cardinality')
    require(re.findall(r'key.sourcefile:\s*("(?:\\.|[^"\\])*?")',request)==[json.dumps(str(path))],'request source/cardinality')
def headerargs(source):
    rows=[l for l in source.splitlines() if l.startswith('// swift-module-flags: ') or l.startswith('// swift-module-flags-ignorable: ')];require(len(rows)==2,'source header cardinality')
    args=[str(SOURCE)];tokens=[x for l in rows for x in shlex.split(l.split(': ',1)[1])];i=0
    flags={'-enable-objc-interop','-formal-cxx-interoperability-mode=off','-strict-memory-safety','-enable-lexical-lifetimes=false','-parse-stdlib','-disable-objc-attr-requires-foundation-module','-enforce-exclusivity=unchecked'}
    while i<len(tokens):
        t=tokens[i]
        if t in {'-target','-target-variant','-target-arch-variant'}:i+=2;continue
        if t=='-target-min-inlining-version':args+=['-Xfrontend',t,'-Xfrontend',tokens[i+1]];i+=2;continue
        args+=['-Xfrontend',t] if t in flags else [t];i+=1
    args+=['-sdk',SDK,'-target',TARGET];require(args.count('-module-name')==1 and args[args.index('-module-name')+1]=='Swift','source header module');return args
def expected_probe():
    forms={'Optional':'Optional<Never>','RangeReplaceableCollection':'(any RangeReplaceableCollection)','MutableCollection':'(any MutableCollection)'}
    return 'import Swift\n\n'+''.join('let _owner'+name+': Any.Type = '+forms.get(name,name)+'.self\n' for name,kind,line,usr in TARGETS)
def raw_usr(name,kind):return 's:4main'+str(len(name))+name+{'enum':'O','struct':'V','protocol':'P'}[kind]
def expanded_input():return ''.join('$s'+usr[2:]+'\n' for name,kind,line,canonical in TARGETS for usr in [raw_usr(name,kind),canonical])
def nominal_tree(root,module,name,kind):
    require(root['kind']=='Global' and len(root['children'])==1 and root['text'] is None and root['index'] is None,'tree root cardinality');node=root['children'][0]
    require(node['kind']=={'enum':'Enum','struct':'Structure','protocol':'Protocol'}[kind] and node['text'] is None and node['index'] is None,'tree nominal kind')
    require(len(node['children'])==2 and [n['kind'] for n in node['children']]==['Module','Identifier'],'tree exact top-level owner shape')
    owner,identifier=node['children'];require(not owner['children'] and not identifier['children'] and owner['index'] is None and identifier['index'] is None,'tree leaf children');require(owner['text']==module and identifier['text']==name,'tree exact namespace/name')
def parse_trees(raw):
    normalized=[];reports={}
    for section in re.split(r'(?=Demangling for \$s)',raw):
        if not section.strip():continue
        lines=section.splitlines();header=re.fullmatch(r'Demangling for (\$s\S+)',lines[0]);require(header is not None,'tree header')
        require(len(lines)>=2 and re.fullmatch(r'[A-Za-z_][A-Za-z0-9_.]*',lines[-1]) is not None,'stdin demangle result shape');usr='s:'+header[1][2:];require(usr not in reports,'duplicate tree section');reports[usr]=lines[-1]
        normalized.append('\n'.join(lines[:-1]+[header[1]+' ---> '+lines[-1]]))
    trees=TREE.trees('\n'.join(normalized))
    for usr,tree in trees.items():
        require(len(tree['children'])==1 and len(tree['children'][0]['children'])==2,'nominal expanded tree/report shape');children=tree['children'][0]['children']
        require([c['kind'] for c in children]==['Module','Identifier'] and reports[usr]==children[0]['text']+'.'+children[1]['text'],'expanded node/result binding')
    return trees
class ExactSwift16:
    def __init__(self):
        self.paths={'source':SOURCE,'headerIndex':HEADER/'raw/Swift.index.txt','headerRequest':HEADER/'requests/Swift.yaml','probe':HERE/'probes/owners.swift','request':HERE/'requests/owners.yaml','typecheckStdout':HERE/'receipts/typecheck.stdout','typecheckStderr':HERE/'receipts/typecheck.stderr','indexStdout':HERE/'raw/owners.index.txt','indexStderr':HERE/'receipts/index.stderr','demangleInput':HERE/'requests/demangle.input.txt','trees':HERE/'raw/trees.txt','demangleStderr':HERE/'receipts/demangle.stderr','processes':HERE/'processes.json'}
        manifest_path=HERE/'capture-inputs.json';manifest_bytes=manifest_path.read_bytes();require(INPUT_MANIFEST_HASH is not None and digest(manifest_bytes)==INPUT_MANIFEST_HASH,'frozen genuine capture input manifest changed');manifest=json.loads(manifest_bytes)
        require(set(manifest)==set(self.paths),'frozen raw capture closure');self.inputs={k:p.read_bytes() for k,p in self.paths.items()};self.pins={k:d['sha256'] for k,d in manifest.items()}
        for key,path in self.paths.items():
            expected_path=str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path);require(manifest[key]['path']==expected_path and manifest[key]['bytes']==len(self.inputs[key]) and digest(self.inputs[key])==self.pins[key],'actual frozen input '+key+' changed')
        self.pins['source']=SOURCE_HASH
        require(digest(self.inputs['source'])==SOURCE_HASH,'actual full SDK source changed');self.source_anchors=nominal_source(self.inputs['source'].decode())
        require(digest((HEADER/'swift-foundation-index-evidence.json').read_bytes())==HEADER_EVIDENCE_HASH,'frozen header capture lineage changed');self.pins['headerIndex']=HEADER_RAW_HASH;self.pins['headerRequest']=HEADER_REQUEST_HASH
        for k,(p,h) in TOOLS.items():require(digest(p.read_bytes())==h,'actual '+k+' bytes changed')
    def validate(self,inputs=None):
        b=dict(self.inputs if inputs is None else inputs);require(set(b)==set(self.inputs),'input closure')
        raw={k:v.decode() for k,v in b.items()};request_identity(raw['headerRequest'],SOURCE);require(compilerargs(raw['headerRequest'])==headerargs(raw['source']),'header request options')
        probe=SCRATCH/'owners.swift';request=SCRATCH/'owners.yaml';request_identity(raw['request'],probe);require(compilerargs(raw['request'])==[str(probe),'-sdk',SDK,'-target',TARGET],'import request options')
        require(raw['probe']==expected_probe(),'exact 16 ordinary import probe');require(raw['demangleInput']==expanded_input(),'exact 32 actual demangle inputs')
        proc=json.loads(raw['processes']);require(set(proc)=={'typecheck','index','demangle'},'process closure')
        commands={'typecheck':[str(TOOLS['compiler'][0]),'-typecheck','-sdk',SDK,'-target',TARGET,str(probe)],'index':[str(TOOLS['sourcekitLsp'][0]),'debug','run-sourcekitd-request','--request-file',str(request)],'demangle':[str(TOOLS['demangler'][0]),'--expand']}
        streams={'typecheck':('typecheckStdout','typecheckStderr'),'index':('indexStdout','indexStderr'),'demangle':('trees','demangleStderr')}
        for name,p in proc.items():
            require(p['argv']==commands[name] and p['cwd']==str(SCRATCH),'actual '+name+' argv/cwd')
            require(type(p['returncode']) is int and p['returncode']==0 and type(p['startedUnixNs']) is int and type(p['endedUnixNs']) is int and p['endedUnixNs']>=p['startedUnixNs'],'actual '+name+' execution result/time')
            for stream,key in zip(['stdout','stderr'],streams[name]):
                expected_path=str(self.paths[key].relative_to(ROOT));require(p[stream]['path']==expected_path and p[stream]['sha256']==digest(b[key]) and p[stream]['bytes']==len(b[key]),'actual '+name+' '+stream+' binding')
            require(p['stdinSha256']==(digest(b['demangleInput']) if name=='demangle' else None),'actual '+name+' stdin binding')
        require(not b['typecheckStdout'] and not b['typecheckStderr'] and not b['indexStderr'] and not b['demangleStderr'],'successful process streams')
        models=nominal_source(raw['source']);entities=records(raw['headerIndex']);references=records(raw['indexStdout']);trees=parse_trees(raw['trees']);expected_usrs={u for name,kind,line,canonical in TARGETS for u in [raw_usr(name,kind),canonical]};require(set(trees)==expected_usrs,'tree exact 32 USR closure');result=[]
        for probe_line,(name,kind,line,canonical) in enumerate(TARGETS,3):
            declarations=models.get(name,[]);require(len(declarations)==1,'source nominal cardinality');d=declarations[0];require(d['line']==line and d['kind']==kind and d['access']=='public' and not d['conditions'],'source exact public nominal/branch')
            require(d==self.source_anchors[name][0],'source exact declaration/attributes identity')
            at=[e for e in entities if e['line']==line and e['column']==d['column']];require(len(at)==1,'physical raw cardinality');e=at[0]
            require(e['name']==name and e['kind']=='source.lang.swift.decl.'+kind and e['usr']==raw_usr(name,kind) and e.get('effective_access')=='source.decl.effective_access.public' and not e.get('is_implicit') and not e['parents'],'physical raw exact identity/access/owner')
            text=expected_probe().splitlines()[probe_line-1];column=text.index(name,text.index('=')+1)+1;at=[r for r in references if r['line']==probe_line and r['column']==column];require(len(at)==1,'import reference cardinality');r=at[0]
            require(r['name']==name and r['kind']=='source.lang.swift.ref.'+kind and r['usr']==canonical and not r.get('is_implicit'),'import exact canonical identity')
            nominal_tree(trees[e['usr']],'main',name,kind);nominal_tree(trees[canonical],'Swift',name,kind)
            result.append({'physicalModule':'Swift','sourceNamespace':'main','canonicalModule':'Swift','name':name,'kind':kind,'line':line,'column':d['column'],'sourceText':d['text'],'sourceConditions':d['conditions'],'sourceAttributes':d['attributes'],'sourceUsr':e['usr'],'canonicalUsr':canonical,'referenceLine':probe_line,'referenceColumn':column,'sourceRawCardinality':1,'importRawCardinality':1,'status':'exact-bounded-physical-to-compiled-import-correspondence'})
        expected_refs=[(1,8,'Swift','source.lang.swift.ref.module','c:@M@Swift'),(3,41,'Never','source.lang.swift.ref.enum','s:s5NeverO')]+[(r['referenceLine'],r['referenceColumn'],r['name'],'source.lang.swift.ref.'+r['kind'],r['canonicalUsr']) for r in result]
        observed_refs=[tuple(r[k] for k in ['line','column','name','kind','usr']) for r in references if r['kind'].startswith('source.lang.swift.ref.')]
        require(collections.Counter(observed_refs)==collections.Counter(expected_refs),'exact import reference closure including module/auxiliary generic')
        for k,v in b.items():require(digest(v)==self.pins[k],'final '+k+' immutable bytes')
        return result
