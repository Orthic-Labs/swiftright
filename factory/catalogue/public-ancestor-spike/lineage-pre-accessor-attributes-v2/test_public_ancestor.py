"""Replay complete artifact & changed actual raw/source acceptance faults."""
import json,re
from pathlib import Path
from types import MappingProxyType
from exact_public_ancestor import Validator,HERE,LINK_HASH,V12_HASH,DEMANGLE_HASH,helper,digest,require,load_artifact

def line_edit(raw,line,old,new):
    rows=raw.splitlines(keepends=True);require(old in rows[line-1],'fault source anchor missing');rows[line-1]=rows[line-1].replace(old,new,1);return ''.join(rows)

def record_span(raw,line,name):
    cursor=0
    while True:
        at=raw.find('key.line: '+str(line)+',',cursor);require(at>=0,'fault exact raw anchor missing')
        start=raw.rfind('{',0,at)
        if 'key.name: '+json.dumps(name) in raw[start:at]:break
        cursor=at+1
    depth=0;quoted=False;escaped=False
    for end in range(start,len(raw)):
        c=raw[end]
        if quoted:
            if escaped:escaped=False
            elif c=='\\':escaped=True
            elif c=='"':quoted=False
        elif c=='"':quoted=True
        elif c=='{':depth+=1
        elif c=='}':
            depth-=1
            if depth==0:
                return start,end+1
    raise ValueError('fault raw record unterminated')

def duplicate_record(raw,line,name):
    start,end=record_span(raw,line,name);return raw[:start]+raw[start:end]+',\n'+raw[start:]

def record_edit(raw,line,name,old,new):
    start,end=record_span(raw,line,name);block=raw[start:end];require(old in block,'fault direct record field missing');return raw[:start]+block.replace(old,new,1)+raw[end:]

def test():
    path=HERE/'public-ancestor-evidence-v2.json.gz';descriptor=json.loads((HERE/'public-ancestor-artifact-v2.json').read_text());v,evidence=load_artifact(path,digest(path.read_bytes()),expected_raw_sha256=descriptor['rawJsonSha256'],expected_raw_bytes=descriptor['rawJsonBytes']);baseline=evidence['resolution']
    require(baseline['fullSourceDeclarationStarts']==17846 and baseline['unreconstructedV12Starts']==0,'actual universe denominator changed')
    faults=[]
    def add(name,key,changed):
        require(changed!=v.inputs[key] and digest(changed)!=v.pins[key],'fault unchanged '+name);faults.append((name,key,changed))
    core=v.inputs['SwiftUICore:source'];ui=v.inputs['SwiftUI:source']
    add('compound-binding-name','SwiftUICore:source',line_edit(core,13604,'m12','wrongName'))
    add('compound-binding-removal','SwiftUICore:source',line_edit(core,13604,', m12: CoreFoundation::CGFloat = 0.0',''))
    add('nominal-ancestor-access','SwiftUI:source',line_edit(ui,4067,'public struct','internal struct'))
    add('nominal-owner-name','SwiftUI:source',line_edit(ui,4067,'ToggleStyleConfiguration','WrongOwner'))
    add('declaration-read-access','SwiftUI:source',line_edit(ui,4080,'public var','internal var'))
    add('declaration-family','SwiftUICore:source',line_edit(core,13604,'var','let'))
    add('source-appended-bytes','SwiftUI:source',ui+'\n// changed actual source bytes\n')
    add('conditional-expression','SwiftUI:source',ui.replace('compiler(>=5.3)','compiler(>=99.0)',1))
    add('annotation-macOS-unavailable','SwiftUI:source',line_edit(ui,236,'unavailable','deprecated'))
    add('added-unindexed-owner-nominal','SwiftUICore:source',core+'\npublic struct ProjectionTransform {}\n')
    index=v.inputs['SwiftUICore:index'];entity=next(e for e in helper.entities(index) if e['line']==13604 and e['name']=='m11')
    for field,old,new in [('usr',entity['usr'],'s:WrongIdentity'),('name','m11','wrongName'),('kind',entity['kind'],'source.lang.swift.decl.enum'),('effective_access',entity['effective_access'],'source.decl.effective_access.internal')]:
        needle='key.'+field+': '+('"'+old+'"' if field in {'usr','name'} else old)
        require(needle in index,'raw field anchor missing');add('raw-'+field,'SwiftUICore:index',record_edit(index,13604,'m11',needle,needle.replace(old,new)))
    add('raw-cardinality','SwiftUICore:index',duplicate_record(index,13604,'m11'))
    add('request-target','SwiftUI:request',v.inputs['SwiftUI:request'].replace('arm64-apple-macosx27.0','arm64-apple-macosx26.0'))
    add('request-extra-flag','SwiftUI:request',v.inputs['SwiftUI:request'].replace('"-module-name"','"-wrong-module-name"'))
    processes=json.loads(v.inputs['processResults']);processes['SwiftUI']['compile']['argv'][0]='/wrong/compiler';add('captured-process-argv','processResults',json.dumps(processes,sort_keys=True,separators=(',',':'))+'\n')
    tree=v.inputs['trees'];first=re.split(r'(?=Demangling for \$s)',tree)[1];add('duplicate-tree','trees',tree+first)
    add('tree-full-namespace','trees',tree.replace('text="SwiftUI"','text="WrongModule"',1))
    add('projected-third-raw-duplicate','SwiftUI:index',duplicate_record(v.inputs['SwiftUI:index'],4080,'$isOn'))
    add('core-header-abi-option','SwiftUICore:request',v.inputs['SwiftUICore:request'].replace('"-module-abi-name"','"-wrong-module-abi-name"'))
    add('core-header-feature-option','SwiftUICore:request',v.inputs['SwiftUICore:request'].replace('"AnyAppleOSAvailability"','"WrongFeature"'))
    graph=json.loads(v.inputs['graphUsrClosure']);graph.pop();add('actual-graph-closure-member','graphUsrClosure',json.dumps(graph,separators=(',',':'))+'\n')
    ast=v.inputs['SwiftUICore:destructorAST'];node=next(n for n in __import__('exact_public_ancestor').destructor.parse_ast(ast,'SwiftUICore') if n['line']==12413)
    add('destructor-ast-access','SwiftUICore:destructorAST',ast.replace(node['raw'],node['raw'].replace('access=open','access=internal'),1))
    add('destructor-ast-cardinality','SwiftUICore:destructorAST',ast+'\n'+node['raw']+'\n')
    add('documentation-internal','SwiftUICore:source',line_edit(core,15758,'visibility: internal','visibility: public'))
    duplicate=duplicate_record(index,13604,'m11')
    add('raw-duplicate-changed-name','SwiftUICore:index',record_edit(duplicate,13604,'m11','key.name: "m11"','key.name: "wrongName"'))
    add('raw-duplicate-changed-kind','SwiftUICore:index',record_edit(duplicate,13604,'m11','key.kind: '+entity['kind'],'key.kind: source.lang.swift.decl.enum'))
    add('raw-physical-column','SwiftUICore:index',record_edit(index,13604,'m11','key.column: 14','key.column: 15'))
    add('core-public-module-option','SwiftUICore:request',v.inputs['SwiftUICore:request'].replace('"-public-module-name"','"-wrong-public-module-name"'))
    add('core-module-name-option','SwiftUICore:request',v.inputs['SwiftUICore:request'].replace('"-module-name"','"-wrong-module-name"'))
    add('core-frontend-forwarding','SwiftUICore:request',v.inputs['SwiftUICore:request'].replace('"-Xfrontend"','"-wrong-Xfrontend"',1))
    add('core-source-abi-header','SwiftUICore:source',core.replace('-module-abi-name SwiftUI','-module-abi-name WrongModule',1))
    ui_index=v.inputs['SwiftUI:index']
    add('extension-raw-duplicate','SwiftUI:index',duplicate_record(ui_index,28,'View'))
    extension=next(e for e in helper.entities(ui_index) if e['line']==28 and e['kind'].startswith('source.lang.swift.decl.extension.'))
    add('extension-raw-kind','SwiftUI:index',record_edit(ui_index,28,'View','key.kind: '+extension['kind'],'key.kind: source.lang.swift.decl.extension.enum'))
    add('extension-source-target','SwiftUI:source',line_edit(ui,28,'View','WrongOwner'))
    getter=next(e for e in helper.entities(ui_index) if e['line']==485 and e['kind'].endswith('.getter'))
    add('accessor-raw-duplicate','SwiftUI:index',duplicate_record(ui_index,485,getter['name']))
    add('accessor-raw-kind','SwiftUI:index',record_edit(ui_index,485,getter['name'],'key.kind: '+getter['kind'],'key.kind: source.lang.swift.decl.enum'))
    add('accessor-source-token','SwiftUI:source',line_edit(ui,485,'get','set'))
    import compiler_children
    typed=next(n for n in compiler_children.ast_nodes(v.inputs['SwiftUI:destructorAST']) if n['line']==485)
    add('accessor-typed-access','SwiftUI:destructorAST',v.inputs['SwiftUI:destructorAST'].replace(typed['raw'],typed['raw'].replace('access=internal','access=public'),1))
    internal_owner=next(e for e in helper.entities(ui_index) if e['line']==421 and e['kind']=='source.lang.swift.decl.struct')
    add('accessor-nonpublic-owner-raw-access','SwiftUI:index',record_edit(ui_index,421,internal_owner['name'],'key.effective_access: source.decl.effective_access.internal','key.effective_access: source.decl.effective_access.public'))
    internal_owner_ast=next(n for a in compiler_children.ast_nodes(v.inputs['SwiftUI:destructorAST']) if a['line']==433 for n in a['owners'] if n['line']==421 and n['kind']=='struct_decl')
    add('accessor-nonpublic-owner-typed-access','SwiftUI:destructorAST',v.inputs['SwiftUI:destructorAST'].replace(internal_owner_ast['raw'],internal_owner_ast['raw'].replace('access=internal','access=public'),1))
    projected_getter=next(e for e in helper.entities(ui_index) if e['line']==4081 and e['kind'].endswith('.getter'))
    add('projected-third-getter','SwiftUI:index',duplicate_record(ui_index,4081,projected_getter['name']))
    generic=next(e for e in helper.entities(ui_index) if e['line']==22206 and e['kind'].endswith('.generic_type_param'))
    parent=generic['sourcekitContext'][-1]
    add('physical-generic-parent-duplicate','SwiftUI:index',duplicate_record(ui_index,parent['line'],parent['name']))
    add('physical-generic-token','SwiftUI:source',line_edit(ui,22206,generic['name'],'WrongGeneric'))
    for name,mutator in [('returncode-bool',lambda p:p.update(returncode=False)),('epoch-bool',lambda p:p.update(startedAtEpochNs=True)),('timestamp',lambda p:p.update(startedAt='2020-01-01T00:00:00.000000Z')),('argv',lambda p:p['argv'].__setitem__(0,'/wrong/tool'))]:
        key='external:DeveloperToolsSupport:receipt';receipt=json.loads(v.inputs[key]);mutator(receipt['process']);add('foreign-process-'+name,key,json.dumps(receipt,sort_keys=True,separators=(',',':'))+'\n')
    add('clang-canonical-namespace','clang:nominal:trees',v.inputs['clang:nominal:trees'].replace('text="__C"','text="WrongNamespace"',1))
    add('clang-import-kind','clang:nominal:index',v.inputs['clang:nominal:index'].replace('key.kind: source.lang.swift.ref.class','key.kind: source.lang.swift.ref.struct',1))
    add('clang-explicit-target','clang:processes',v.inputs['clang:processes'].replace('arm64-apple-macosx27.0','arm64-apple-macosx26.0',1))
    for process_kind in ('compile','run'):
        process=json.loads(v.inputs['processResults']);process['SwiftUI'][process_kind]['exitCode']=False
        add('branch-'+process_kind+'-boolean-exit','processResults',json.dumps(process,sort_keys=True,separators=(',',':'))+'\n')
    receipts=[]
    for name,key,changed in faults:
        raw=dict(v.inputs);raw[key]=changed
        try:v.accept(baseline,raw)
        except (ValueError,KeyError) as error:receipts.append({'name':name,'rawInput':key,'baselineAccepted':True,'beforeSha256':v.pins[key],'afterSha256':digest(changed),'rejected':True,'reason':str(error)})
        else:raise AssertionError('accepted actual input fault '+name)
    result={'kind':'production-public-ancestor-raw-fault-replay','artifactSha256':digest(path.read_bytes()),'baselineWholeArtifactEqual':True,'faultCount':len(receipts),'faults':receipts}
    (HERE/'public-ancestor-faults-v2.json').write_text(json.dumps(result,sort_keys=True,separators=(',',':'))+'\n');print(json.dumps({'wholeArtifactEqual':True,'rejectedRawFaults':len(receipts)}))
if __name__=='__main__':test()
