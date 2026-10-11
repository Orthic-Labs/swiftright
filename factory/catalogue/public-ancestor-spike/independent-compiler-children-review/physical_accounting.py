"""Independent bounded physical accounting; never asserts tree/USR equivalence."""
import copy, hashlib, importlib.util, json, re
from pathlib import Path

HERE=Path(__file__).resolve().parent
BASE=HERE.parent
ROOT=BASE.parents[2]
def require(ok,reason):
    if not ok: raise ValueError(reason)
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def parsed_ast(text):
    stack=[]; funcs=[]
    for raw in text.splitlines():
        indent=len(raw)-len(raw.lstrip())
        while stack and stack[-1]['indent']>=indent: stack.pop()
        kind=re.match(r'\s*\((class_decl|struct_decl|enum_decl|protocol|extension_decl|func_decl)\b',raw)
        loc=re.search(r'range=\[(.*?):(\d+):(\d+) - line:(\d+):(\d+)\]',raw)
        if not kind or not loc: continue
        quoted=re.findall(r'"(?:[^"\\]|\\.)*"',raw[loc.end():])
        n={'kind':kind[1],'source':loc[1],'line':int(loc[2]),'column':int(loc[3]),'endLine':int(loc[4]),'endColumn':int(loc[5]),'name':json.loads(quoted[0]) if quoted else None,'generic':json.loads(quoted[1]) if len(quoted)>1 else None,'raw':raw,'indent':indent}
        if n['kind']=='func_decl': n['owners']=copy.deepcopy(stack);funcs.append(n)
        stack.append(n)
    return funcs

def evaluate(row, records, funcs, source, source_path, trees):
    e=row['entity'];parent=row['parent']; ctx=e.get('sourcekitContext',[])
    require(e['kind']=='source.lang.swift.decl.generic_type_param','raw-child-kind')
    require(sum(x==e for x in records)==1 and sum(x['line']==e['line'] and x['column']==e['column'] for x in records)==1,'raw-child-identity-cardinality')
    keys=('kind','name','usr','line','column')
    require(len(ctx)==2 and all(ctx[-1].get(k)==parent.get(k) for k in keys),'raw-parent-context')
    matches=[x for x in records if all(x.get(k)==parent.get(k) for k in keys)]
    require(len(matches)==1,'raw-parent-identity-cardinality')
    require(row['childTree']==trees.get(e['usr']) and row['parentTree']==trees.get(parent['usr']),'actual-tree-projection')
    roots=row['childTree']['children']
    require(len(roots)==1 and roots[0]['kind']=='GenericTypeParamDecl' and len(roots[0]['children'])==3 and roots[0]['children'][1]['kind']=='Identifier' and roots[0]['children'][1]['text']==e['name'] and roots[0]['children'][2]['kind']=='Type','actual-child-tree-family-name')
    ext=ctx[-2]
    require(ext['kind'] in {'source.lang.swift.decl.extension.struct','source.lang.swift.decl.extension.protocol'} and sum(all(x.get(k)==ext.get(k) for k in keys) for x in records)==1,'raw-extension-identity-cardinality')
    nodes=[n for n in funcs if n['source']==source_path and n['line']==parent['line'] and n['name']==parent['name']]
    require(len(nodes)==1,'ast-function-cardinality')
    n=nodes[0];require(len(n['owners'])==1,'ast-parent-depth');a=n['owners'][0]
    require(a['kind']=='extension_decl' and a['source']==source_path and a['line']==ext['line'] and a['name']==ext['name'] and a['line']<=n['line']<=n['endLine']<=a['endLine'],'ast-extension-parent')
    line=source.splitlines()[e['line']-1];name=parent['name'].split('(')[0]
    require(e['line']==parent['line'] and line[parent['column']-1:].startswith(name+'<'),'source-parent-token')
    require(line[n['column']-1:parent['column']-1]==('static func ' if parent['kind']=='source.lang.swift.decl.function.method.static' else 'func '),'source-ast-function-position')
    start=parent['column']-1+len(name);end=line.index('>',start)
    require(start<e['column']-1<end and re.match(re.escape(e['name'])+r'(?![\w$])',line[e['column']-1:]) is not None,'source-generic-token-position')
    require(n['generic']=='<'+e['name']+'>','ast-generic-name')
    static=parent['kind']=='source.lang.swift.decl.function.method.static'
    require(parent['kind'] in {'source.lang.swift.decl.function.method.static','source.lang.swift.decl.function.method.instance'} and static==bool(re.search(r'\bstatic\s*$',n['raw'])) and static==bool(re.search(r'\bstatic\s+func\s*$',line[:parent['column']-1])),'raw-source-ast-static-kind')
    return {'status':'attributed-physical-parent-component-tree-disagreement','childUsr':e['usr'],'parentUsr':parent['usr'],'sourceKey':[row['module'],e['line'],e['column'],e['name']],'astFunction':n,'childTree':row['childTree'],'parentTree':row['parentTree'],'canonicalIdentityPromotion':False,'standalonePublicAPI':False,'parentAPIQualification':'independent'}

def run():
    parser=ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py'
    require(digest(parser)=='83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5','raw-parser-pin')
    s=importlib.util.spec_from_file_location('frozen_raw',parser);h=importlib.util.module_from_spec(s);s.loader.exec_module(h)
    rows=json.loads((HERE/'ten-observed-pairs.json').read_text());results=[];faults=[];pins={}
    tp=BASE/'inputs-v1/trees.txt'
    require(digest(tp)=='68c45712746ab41ed57854d0e44b9a9d37e00d107c9ba0d0b500d6d8eb2d0d72','actual-trees-pin')
    trees=h.trees(tp.read_text());pins[str(tp.relative_to(ROOT))]=digest(tp)
    for module in ('SwiftUI','SwiftUICore'):
        ip=ROOT/'factory/catalogue/compiler-cursor-spike/index-interface-output.txt' if module=='SwiftUI' else BASE/'core-header-index-v1/sourcekit-index-core-header.stdout'
        sp=BASE/f'inputs-v1/{module}-source.txt';ap=BASE/f'inputs-v1/{module}-destructorAST.txt'
        records=h.entities(ip.read_text());source=sp.read_text();funcs=parsed_ast(ap.read_text());source_path=next(n['source'] for n in funcs)
        for path in (ip,sp,ap):pins[str(path.relative_to(ROOT))]=digest(path)
        for row in [r for r in rows if r['module']==module]:
            results.append(evaluate(row,records,funcs,source,source_path,trees))
            for label in ('parent_usr','parent_kind','child_usr','child_kind','child_column','extension_line','source_token','duplicate_parent','ast_extension','child_tree','parent_tree'):
                bad=copy.deepcopy(row);bs=source;br=records;bf=funcs
                if label=='parent_usr':bad['parent']['usr']+='x'
                if label=='parent_kind':bad['parent']['kind']='source.lang.swift.decl.struct'
                if label=='child_usr':bad['entity']['usr']+='x'
                if label=='child_kind':bad['entity']['kind']='source.lang.swift.decl.var.instance'
                if label=='child_column':bad['entity']['column']+=1
                if label=='extension_line':bad['entity']['sourcekitContext'][0]['line']+=1
                if label=='source_token':ls=source.splitlines();i=bad['entity']['line']-1;c=bad['entity']['column']-1;ls[i]=ls[i][:c]+'X'+ls[i][c+1:];bs='\n'.join(ls)
                if label=='duplicate_parent':br=records+[next(x for x in records if x['usr']==row['parent']['usr'])]
                if label=='ast_extension':bf=copy.deepcopy(funcs);next(n for n in bf if n['line']==row['parent']['line'] and n['name']==row['parent']['name'])['owners'][0]['line']+=1
                if label=='child_tree':bad['childTree']['children'][0]['kind']='Function'
                if label=='parent_tree':bad['parentTree']['children'][0]['kind']='Variable'
                try:evaluate(bad,br,bf,bs,source_path,trees)
                except ValueError as error:faults.append({'module':module,'line':row['entity']['line'],'fault':label,'reason':str(error)})
                else:raise AssertionError(label)
    return {'scope':'ten observed raw SourceKit generic components only','inputPins':pins,'rows':results,'faults':faults,'noTreeNormalization':True,'noCanonicalIdentityPromotion':True}
if __name__=='__main__':
    out=run();(HERE/'physical-accounting-review.json').write_text(json.dumps(out,indent=2)+'\n');print(len(out['rows']),len(out['faults']))
