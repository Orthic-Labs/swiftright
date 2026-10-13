"""Typed accessor/source/parent joins from captured whole-interface AST bytes."""
import re,json

def require(ok,reason):
    if not ok:raise ValueError(reason)

def ast_nodes(text):
    stack=[];result=[]
    for raw in text.splitlines():
        indent=len(raw)-len(raw.lstrip())
        while stack and stack[-1]['indent']>=indent:stack.pop()
        kind=re.match(r'\s*\((class_decl|struct_decl|enum_decl|protocol|extension_decl|var_decl|subscript_decl|accessor_decl)\b',raw)
        if not kind:continue
        location=re.search(r'range=\[(.*?):(\d+):(\d+) - line:(\d+):(\d+)\]',raw)
        if not location:continue
        access=re.search(r'\baccess=(public|open|internal|package|private|fileprivate)\b',raw)
        name=re.match(r'\s*("(?:[^"\\]|\\.)*")',raw[location.end():])
        node={'kind':kind[1],'source':location[1],'line':int(location[2]),'column':int(location[3]),'endLine':int(location[4]),'endColumn':int(location[5]),'access':access[1] if access else None,'name':json.loads(name[1]) if name else None,'raw':raw,'indent':indent}
        if node['kind']=='accessor_decl':
            family=re.search(r'\b(get|set) for=("(?:[^"\\]|\\.)*")',raw)
            if not family:continue
            node.update(family=family[1],propertyName=json.loads(family[2]),owners=[dict(n) for n in stack]);result.append(node)
        else:stack.append(node)
    return result

def child_tree(child,parent,family):
    child_roots=child['children'];parent_roots=parent['children']
    child_static=len(child_roots)==1 and child_roots[0]['kind']=='Static'
    parent_static=len(parent_roots)==1 and parent_roots[0]['kind']=='Static'
    require(child_static==parent_static,'accessor static/full parent tree disagreement')
    if child_static:child_roots=child_roots[0]['children'];parent_roots=parent_roots[0]['children']
    require(len(child_roots)==len(parent_roots)==1,'accessor full tree root cardinality')
    node=child_roots[0]
    require(node['kind']==('Getter' if family=='get' else 'Setter') and len(node['children'])==1 and node['children'][0]==parent_roots[0] and parent_roots[0]['kind'] in {'Variable','Subscript'},'accessor exact family/full parent tree identity')

def accessor(entity,parent,nodes,trees,source_path,source):
    family='get' if entity['kind']=='source.lang.swift.decl.function.accessor.getter' else 'set'
    require(entity['kind'] in {'source.lang.swift.decl.function.accessor.getter','source.lang.swift.decl.function.accessor.setter'},'accessor raw family')
    matches=[n for n in nodes if n['source']==source_path and n['line']==entity['line'] and n['column']==entity['column']]
    require(len(matches)==1,'accessor actual typed AST physical cardinality')
    node=matches[0]
    reparsed=ast_nodes(node['raw'])
    require(len(reparsed)==1 and {k:v for k,v in reparsed[0].items() if k!='owners'}=={k:v for k,v in node.items() if k!='owners'},'accessor AST fields disagree with actual raw header')
    for ancestor in node['owners']:
        location=re.search(r'range=\[(.*?):(\d+):(\d+) - line:(\d+):(\d+)\]',ancestor['raw'])
        access=re.search(r'\baccess=(public|open|internal|package|private|fileprivate)\b',ancestor['raw'])
        kind=re.match(r'\s*\((\w+)\b',ancestor['raw']);name=re.match(r'\s*("(?:[^"\\]|\\.)*")',ancestor['raw'][location.end():]) if location else None
        require(kind and ancestor['kind']==kind[1] and ancestor['name']==(json.loads(name[1]) if name else None),'accessor AST ancestor kind/name disagree with actual raw header')
        require(location and ancestor['source']==location[1] and ancestor['line']==int(location[2]) and ancestor['column']==int(location[3]) and ancestor['endLine']==int(location[4]) and ancestor['endColumn']==int(location[5]) and ancestor['access']==(access[1] if access else None),'accessor AST ancestor fields disagree with actual raw header')
    require(node['family']==family and node['access'] in {'public','open','internal','package','private','fileprivate'} and 'interface_type=' in node['raw'] and '<error' not in node['raw'],'accessor typed AST family/access')
    require(node['owners'] and node['owners'][-1]['kind'] in {'var_decl','subscript_decl'},'accessor actual AST parent family')
    owner=node['owners'][-1]
    require(entity.get('sourcekitContext') and all(entity['sourcekitContext'][-1].get(k)==parent.get(k) for k in ('kind','name','usr','line','column')),'accessor raw exact parent context identity')
    require((owner['kind']=='var_decl' and parent['kind'] in {'source.lang.swift.decl.var.instance','source.lang.swift.decl.var.static','source.lang.swift.decl.var.class','source.lang.swift.decl.var.global'}) or (owner['kind']=='subscript_decl' and parent['kind']=='source.lang.swift.decl.function.subscript'),'accessor actual raw/AST parent family disagreement')
    parent_columns={parent['column']}
    if owner['kind']=='subscript_decl':
        source_line=source.splitlines()[parent['line']-1]
        before=source_line[:parent['column']-1]
        static=re.search(r'\bstatic\s+$',before)
        if static:parent_columns.add(static.start()+1)
    require(owner['source']==source_path and owner['line']==parent['line'] and owner['column'] in parent_columns and owner['line']<=node['line'],'accessor exact physical AST parent position')
    require(entity['name']==('getter:' if family=='get' else 'setter:')+parent['name'] and node['propertyName']==parent['name'],'accessor exact raw/typed property name')
    require(entity['usr'] in trees and parent['usr'] in trees,'accessor actual child/parent compiler trees absent')
    child_tree(trees[entity['usr']],trees[parent['usr']],family)
    return node

def parameter(entity,parent,trees,source):
    require(entity['kind']=='source.lang.swift.decl.generic_type_param','generic parameter raw family')
    require(entity['usr'] in trees and parent['usr'] in trees,'generic parameter actual trees absent')
    roots=trees[entity['usr']]['children'];require(len(roots)==1 and roots[0]['kind']=='GenericTypeParamDecl','generic parameter full tree family')
    children=roots[0]['children'];require(len(children)==3 and children[1]['kind']=='Identifier' and children[1]['text']==entity['name'] and children[2]['kind']=='Type','generic parameter exact declaration identity')
    owner=children[0]
    if owner['kind']=='OpaqueReturnTypeOf':
        require(len(owner['children'])==1,'generic parameter typed owner cardinality');owner=owner['children'][0]
    require(trees[parent['usr']]['children']==[owner],'generic parameter exact full parent tree')
    line=source.splitlines()[entity['line']-1];token=line[entity['column']-1:]
    require(re.match(r'`?'+re.escape(entity['name'])+r'`?(?![\w$])',token) is not None and entity['line']==parent['line'],'generic parameter actual source token/parent line')
    return roots[0]

def initializer(entity,parent,trees,source):
    require(entity['usr'] in trees and parent['usr'] in trees,'property initializer actual trees absent')
    roots=trees[entity['usr']]['children']
    require(len(roots)==1 and roots[0]['kind']=='InitAccessor' and roots[0]['children']==trees[parent['usr']]['children'],'property initializer exact typed parent tree')
    require(entity['name']=='init:'+parent['name'] and source.splitlines()[entity['line']-1][entity['column']-1:].startswith('init('),'property initializer exact source token/name')
    require(entity.get('effective_access')=='source.decl.effective_access.internal','property initializer actual compiler access')
    return roots[0]

def physical_parameter(entity,parent,extension,source,ast_text,source_path):
    """Bound observed generic token to typed physical owner; no tree ID transfer."""
    require(entity['kind']=='source.lang.swift.decl.generic_type_param','physical generic component family')
    context=entity.get('sourcekitContext',[])
    require(len(context)>=2 and all(context[-1].get(k)==parent.get(k) for k in ('kind','name','usr','line','column')) and all(context[-2].get(k)==extension.get(k) for k in ('kind','name','usr','line','column')),'physical generic exact raw parent/extension context')
    require(parent['kind'] in {'source.lang.swift.decl.function.method.instance','source.lang.swift.decl.function.method.static'} and extension['kind'].startswith('source.lang.swift.decl.extension.'),'physical generic function/extension family')
    stack=[];matches=[]
    for raw in ast_text.splitlines():
        indent=len(raw)-len(raw.lstrip())
        while stack and stack[-1]['indent']>=indent:stack.pop()
        kind=re.match(r'\s*\((class_decl|struct_decl|enum_decl|protocol|extension_decl|func_decl)\b',raw)
        location=re.search(r'range=\[(.*?):(\d+):(\d+) - line:(\d+):(\d+)\]',raw)
        if not kind or not location:continue
        quoted=re.findall(r'"(?:[^"\\]|\\.)*"',raw[location.end():])
        node={'kind':kind[1],'source':location[1],'line':int(location[2]),'column':int(location[3]),'endLine':int(location[4]),'endColumn':int(location[5]),'name':json.loads(quoted[0]) if quoted else None,'raw':raw,'indent':indent}
        if kind[1]=='func_decl' and node['source']==source_path and node['line']==parent['line'] and node['name']==parent['name']:
            matches.append((node,list(stack),[json.loads(x) for x in quoted]))
        stack.append(node)
    require(len(matches)==1,'physical generic typed function cardinality')
    function,owners,quoted=matches[0]
    require(owners and owners[-1]['kind']=='extension_decl','physical generic typed extension ancestry')
    owner=owners[-1]
    require(owner['source']==source_path and owner['line']==extension['line'] and owner['name']==extension['name'] and owner['line']<=function['line']<=function['endLine']<=owner['endLine'],'physical generic exact typed extension/source range')
    require(len(quoted)>=2 and quoted[1]=='<'+entity['name']+'>' and 'interface_type=' in function['raw'] and '<error' not in function['raw'],'physical generic exact AST generic signature')
    line=source.splitlines()[parent['line']-1];base=parent['name'].split('(',1)[0]
    require(line[function['column']-1:].startswith(('func ','static func ')) and line[parent['column']-1:].startswith(base+'<') and re.match(r'`?'+re.escape(entity['name'])+r'`?(?![\w$])',line[entity['column']-1:]) and entity['line']==parent['line'],'physical generic exact source tokens')
    require((re.search(r'\bstatic(?:\s|$)',function['raw']) is not None)==(parent['kind']=='source.lang.swift.decl.function.method.static'),'physical generic typed/raw static family')
    return {'typedFunction':function,'typedExtension':owner,'genericSignature':quoted[1]}
