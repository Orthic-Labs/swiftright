#!/usr/bin/env python3
"""Independent exact Swift physical/import raw facts; no namespace alias."""
import hashlib, importlib.util, json, re, shlex
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
BASE=ROOT/'factory/catalogue/public-ancestor-spike'
CAP=BASE/'external-owner-capture/swift-stdlib-v1'
HEADER=BASE/'external-owner-header-index-v1/swift-foundation'
EXPECTED={'Optional':'enum','Never':'enum',**{n:'struct' for n in ['Float','Double','Int','Int8','Int16','Int32','Int64','UInt','UInt8','UInt16','UInt32','UInt64']},'RangeReplaceableCollection':'protocol','MutableCollection':'protocol'}
def sha(b):return 'sha256:'+hashlib.sha256(b).hexdigest()
def pin(p,expected=None):
    p=Path(p);b=p.read_bytes();h=sha(b)
    if expected:assert h==expected,(p,h,expected)
    return {'path':str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p),'sha256':h,'bytes':len(b)}
def load(name,path):
    s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
def records(raw):
    stack=[];out=[]
    for line in raw.splitlines():
        if match:=re.fullmatch(r'(\s*)\{',line):stack.append({'indent':len(match[1]),'fields':{}});continue
        if match:=re.fullmatch(r'(\s*)\},?',line):
            assert stack and stack[-1]['indent']==len(match[1]),'raw closing structure mismatch'
            record=stack.pop()['fields']
            if all(k in record for k in ['kind','name','usr','line','column']):
                record['parentDeclarations']=[dict(p['fields']) for p in stack if p['fields'].get('kind','').startswith('source.lang.swift.decl.')];out.append(record)
            continue
        match=re.fullmatch(r'(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?),?',line)
        if match and stack and len(match[1])==stack[-1]['indent']+2:
            value=match[3].removesuffix(',');value=json.loads(value) if value.startswith('"') else int(value) if value.isdigit() else value
            assert match[2] not in stack[-1]['fields'],'duplicate raw identity field';stack[-1]['fields'][match[2]]=value
    assert not stack,'unterminated raw structure'
    return out
def main():
    evidence=json.loads((CAP/'swift-stdlib-evidence.json').read_text());hd=json.loads((HEADER/'swift-foundation-index-evidence.json').read_text());module=next(m for m in hd['modules'] if m['module']=='Swift')
    pins=[pin(Path(__file__)),pin(CAP/'swift-stdlib-evidence.json'),pin(HEADER/'swift-foundation-index-evidence.json')]
    def walk(v):
        if isinstance(v,dict):
            if 'path' in v and 'sha256' in v:
                p=Path(v['path']);pins.append(pin(p if p.is_absolute() else ROOT/p,v['sha256']))
            for x in v.values():walk(x)
        elif isinstance(v,list):
            for x in v:walk(x)
    walk(evidence['inputs']);walk(evidence['toolchain']);walk(hd['toolchain']);walk(module)
    source=Path(module['source']['path']).read_text();lines=source.splitlines()
    lexpath=BASE/'lexical_model_v2.py';pins.append(pin(lexpath,'sha256:cc6d4dab563f713b91c0ef1f29cbb214a3c129c8f5f3823f438ac24aef75cdd6'));lex=load('frozen_lexical_code',lexpath)
    code=lex.code_lines(source);depth=0;conditions=[];physical={}
    for number,(text,structural) in enumerate(zip(lines,code),1):
        literal=structural.strip()
        if literal.startswith('#if '):conditions.append({'ifLine':number,'branchLine':number,'expression':literal[4:]})
        elif literal.startswith('#elseif ') or literal=='#else':
            assert conditions;conditions[-1]={**conditions[-1],'branchLine':number,'expression':literal}
        elif literal=='#endif':assert conditions;conditions.pop()
        f=lex.fields(structural)
        if f and depth==0 and f['name'] in EXPECTED and f['kind'] in {'struct','enum','protocol'}:
            physical.setdefault(f['name'],[]).append({'line':number,'fields':f,'conditions':[dict(c) for c in conditions],'text':text})
        depth+=structural.count('{')-structural.count('}');assert depth>=0
    assert depth==0 and not conditions
    header_rows=[l for l in lines if l.startswith('// swift-module-flags: ') or l.startswith('// swift-module-flags-ignorable: ')];assert len(header_rows)==2
    args=[module['source']['path']];tokens=[x for l in header_rows for x in shlex.split(l.split(': ',1)[1])];i=0
    forwarded={'-enable-objc-interop','-formal-cxx-interoperability-mode=off','-strict-memory-safety','-enable-lexical-lifetimes=false','-parse-stdlib','-disable-objc-attr-requires-foundation-module','-enforce-exclusivity=unchecked'}
    while i<len(tokens):
        t=tokens[i]
        if t in {'-target','-target-variant','-target-arch-variant'}:i+=2;continue
        if t=='-target-min-inlining-version':args+=['-Xfrontend',t,'-Xfrontend',tokens[i+1]];i+=2;continue
        args+=['-Xfrontend',t] if t in forwarded else [t];i+=1
    args+=['-sdk',hd['sdk'],'-target',hd['target']]
    request=(ROOT/module['request']['path']).read_text();actual=json.loads('['+re.search(r'key.compilerargs:\s*\[(.*?)\]',request,re.S)[1]+']');assert actual==args and actual[actual.index('-module-name')+1]=='Swift'
    assert module['process']['exit']==0 and module['process']['cwd']==str(ROOT)
    raw=records((ROOT/module['process']['stdout']['path']).read_text());refs=records((CAP/'raw/swift-stdlib-targets.index.txt').read_text());probe=(CAP/'probes/swift-stdlib-targets.swift').read_text();pins.append(pin(CAP/'probes/swift-stdlib-targets.swift'))
    import_request=(CAP/'requests/swift-stdlib-targets.yaml').read_text();import_args=json.loads('['+re.search(r'key.compilerargs:\s*\[(.*?)\]',import_request,re.S)[1]+']');assert import_args==[str(CAP/'probes/swift-stdlib-targets.swift'),'-sdk',hd['sdk'],'-target',hd['target']]
    joins=[]
    for n,(name,kind) in enumerate(EXPECTED.items(),3):
        assert len(physical.get(name,[]))==1;src=physical[name][0];assert src['fields']['kind']==kind and re.search(r'\bpublic\s+'+kind+r'\s+',src['text']) and not src['conditions']
        column=lines[src['line']-1].index(name)+1;all_at_position=[r for r in raw if r['line']==src['line'] and r['column']==column];assert len(all_at_position)==1;decl=all_at_position[0]
        assert decl['kind']=='source.lang.swift.decl.'+kind and decl['name']==name and decl['effective_access']=='source.decl.effective_access.public' and not decl.get('is_implicit') and not decl['parentDeclarations']
        assert decl['usr']=='s:4main'+str(len(name))+name+{'enum':'O','struct':'V','protocol':'P'}[kind]
        pline=probe.splitlines()[n-1];assert '_owner'+name+':' in pline;pc=pline.index(name,pline.index('=')+1)+1;at=[r for r in refs if r['line']==n and r['column']==pc];assert len(at)==1;ref=at[0]
        assert ref['name']==name and ref['kind']=='source.lang.swift.ref.'+kind and not ref.get('is_implicit')
        joins.append({'name':name,'kind':kind,'physicalSourceLine':src['line'],'physicalSourceColumn':column,'sourceDeclaration':src['text'],'sourceConditions':src['conditions'],'sourceTopLevel':True,'sourceAccess':'public','rawSourceUsr':decl['usr'],'rawSourceNamespace':'main','importProbeLine':n,'importProbeColumn':pc,'canonicalImportUsr':ref['usr'],'canonicalOrdinaryDemangle':'Swift.'+name})
    assert (CAP/'receipts/demangle.stdout').read_text().splitlines()==['Swift.'+n for n in EXPECTED]
    pins=list({p['path']:p for p in pins}.values())
    result={'kind':'independent-swift-stdlib-bounded-correspondence-raw-review','status':'raw-witnesses-reconstructed-production-guard-pending','witnessCount':16,'sourceNamespaceMismatchPreserved':True,'sourceRequestedModule':'Swift','sourceActualNominalUsrModule':'main','compiledImportNominalModule':'Swift','sourceHeaderRows':header_rows,'exactHeaderRequestArgs':args,'pins':pins,'witnesses':joins,'fullParserFinding':{'parser':'lexical_model_v2.py','sourceLine':8790,'text':'      let key = k as? DerivedKey,','failure':'unparsed compound declaration binding','boundedScopeMethod':'code_lines strings/comments removed; complete balanced braces & conditional stack; exact top-level nominal fields/cardinality before raw identity filters'},'productionRequirements':['exact 16 witness allowlist; no general main→Swift alias','full structural raw main & canonical Swift Module/name/kind/path trees','exact physical source token/cardinality/access/attributes/conditional & imported token cardinality','pinned source/header/request/tool/process bytes & SDK/target','nonvacuous wrong name/module/USR/kind/outer/source branch/reference duplicate/extra target controls'],'conclusion':'Each independently reconstructed top-level public physical declaration can supply textual access lineage for its exact ordinary compiled import identity once full structural trees & production semantic controls are frozen.'}
    (HERE/'swift-stdlib-correspondence-review-v1.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print('16 exact physical public/source + ordinary import witnesses reconstructed; main namespace preserved.')
if __name__=='__main__':main()
