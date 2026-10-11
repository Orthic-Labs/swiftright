"""Independent whole-interface visibility census. Ambiguity is a held result."""
from __future__ import annotations
import copy,hashlib,importlib.util,json,re,sys,subprocess,mmap,shlex,tempfile,gzip
from contextlib import ExitStack
from collections import Counter,defaultdict
from functools import lru_cache
from pathlib import Path
from types import MappingProxyType
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
from lexical_model_v2 import model,NOMINAL,code_lines
from external_scopes import scopes as external_scopes
import compiler_children
V12=ROOT/'factory/catalogue/evidence/interface-audit-v12-candidate.json'
LINK=ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json'
V12_HASH='sha256:6f0384e8dfaa1bb21f96c3153cb02425912b6425cfdd534eb01a7f2ab71e1d13'
LINK_HASH='sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec'
HELPER=ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py'
STRICT=ROOT/'factory/catalogue/compiler-cursor-spike/strict_match.py'
HELPER_HASH='sha256:83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5'
STRICT_HASH='sha256:089ed03a7738cfe3ee456e0517acb8039517b562a7237592f4c4d4cad4729f8a'
LEXICAL_HASH='sha256:cc6d4dab563f713b91c0ef1f29cbb214a3c129c8f5f3823f438ac24aef75cdd6'
DEMANGLE_HASH='sha256:ae7da66c8a56fb3b90817c10eb816c82e25bf7a26ae0158effbda223f7f0fefe'
SCRATCH=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/f1-residuals/public-ancestor-v1')
PUBLIC={'public','open'}
PROJECTED_DUPLICATES={('SwiftUI',4080,'$isOn'),('SwiftUI',5533,'$isExpanded'),('SwiftUI',9717,'$document'),('SwiftUI',23750,'$document'),('SwiftUI',32822,'$selection')}
DUPLICATE_PROOF=ROOT/'factory/catalogue/duplicate-identity-spike/exact-identity-candidate.json'
DUPLICATE_PROOF_HASH='sha256:23c4d70c6b29c078bc8bc4f824ee30b304b882f3beac7ebdeaf69281c2edbf3e'
GRAPH_ARCHIVE_FOLDER=ROOT/'factory/catalogue/raw-symbolgraph-archive-v1'
GRAPH_READER_HASH='sha256:2f6a07cd7c025449dfd9838a0b14fd71c10de94ed7f1254d5312e4c8243b8c06'
GRAPH_ARCHIVE_HASH='sha256:6ddc54fe90bffd954f415963450cfa04d19d94070631b88619635826ce9139e3'
SWIFT16_FOLDER=HERE/'external-owner-capture/swift-stdlib-process-v2'
SWIFT16_GUARD_HASH='sha256:78620db51cdc47da5c1cafcb3f546cea918b67c8a3c5dcc5131b83988e652a0e'
SWIFT16_PROOF_HASH='sha256:26e0d888d6c985bf30615cc4a986b0418b6fbf7efd22252fc6f427a1fd5c341b'
SWIFT16_MANIFEST_HASH='sha256:c760bc8bb37e7c02aaa6123f379293488d5ab3b840282d4c75e060486d456c09'
SWIFT16_WRAPPER_HASH='sha256:d3685592ec84c56a1fa1b15a200b4720377d6ccf1ff2e63bc0d7e5924e3a9a90'
CLANG_FOLDER=HERE/'external-owner-capture/clang-owner-guard-v1'
CLANG_SOURCE_HASHES={'exact_clang.py':'sha256:d7e2c57dba42a12edaefe3abb3e3cb84ed1748dbcc1c3a62aa4b38f7a4691951','ast_reader.py':'sha256:3657d0cc295f31d2540fc79e7589a3857caf8eb5e8bfa616c404af19961f0df9','nominal_bridge.py':'sha256:25abe42b1b2c693d2b4dfac21096c90c6a9504d58cf98c273d21777244a0af49'}
CLANG_MANIFEST_HASH='sha256:463a3a05f3f27d4ac330115a8af344b6f61d9767ad7c06af0d7c3a8e8014ad13'
CLANG_PROOF_HASH='sha256:dd67e39c164b618d40f1f7770d7f8bf6bb63562c843c0c70428092261e2bbba2'
RESOLVER_HASH='sha256:28c7ddd5974534efc13cb93d6030ce64fadb752e6c98212205f02c4b9787a8d4'
DESTRUCTOR_WRAPPER_HASH='sha256:77259710191f358cd9add04a1350ec5b98821d7bbe3337e7a26a7b84b4fe4970'
EXTERNAL_PROOFS=[('external-owner-header-index-v1/swift-foundation/swift-foundation-index-evidence.json','sha256:7f332345a044d54ec4617fa06c7bf73513235c08f4e7aa767446924a0842f3bb')]
FOREIGN_FOLDER=HERE/'external-owner-header-index-v1/developer-spatial-symbols-process-v2'
FOREIGN_PROOF_HASH='sha256:f9ceb28c3a6d15605287693cf947380815265602bc47b127a57319f760b939e2'
FOREIGN_RECEIPT_HASHES={'DeveloperToolsSupport':'sha256:1d7eb7c259332f9544d029751b637386afe005b0e3646a8933927e206fc5cfa5','Spatial':'sha256:e71e7c495515cd65ac0ee87caf0ff5adf6f64dc69e20c619782112598eee4dfe','Symbols':'sha256:3795ee4c2dc2959f3c8ca55cc54a0fdca3f54ddf90e789ec52ced2d6b509a988','CoreFoundation':'sha256:9c2eea7bf7cea31ecb97c0381757162bfbb85893da2768001904a2823c533bfb'}
EXTERNAL_TARGETS={'Swift':{'Optional','Never','Float','Double','Int','Int8','Int16','Int32','Int64','UInt','UInt8','UInt16','UInt32','UInt64','RangeReplaceableCollection','MutableCollection'},'Foundation':{'AttributedString','AttributeScopes','FormatStyle','AttributeDynamicLookup'},'DeveloperToolsSupport':{'Preview','PreviewTrait'},'Spatial':set(),'Symbols':{'WiggleSymbolEffect'},'CoreFoundation':{'CGFloat'}}
CORE_FOLDER=HERE/'core-header-index-v1'
CORE_PINS={'index':('sourcekit-index-core-header.stdout','sha256:06ec81f980bad90c171dad909315fe0555df35578efff4a1e173a901babd5520'),'request':('request-index-core-header.yaml','sha256:48246455beb6ead6d27c75df9e8715801be7b8d4aeb22b59e1853f0662a22539'),'indexReceipt':('run-receipt.json','sha256:69b9f36244cbf45bb7f86aa5e9a768f120c1908daa6b0d1ffd41e77bed4994b7')}
DESTRUCTOR_FOLDER=HERE/'destructor-api-eligibility-proof'
DESTRUCTOR_GUARD_HASH='sha256:391cbf4c02748ed4b995936f606dcee2ab95e007767e8dd498b4b3d5f745e997'
DESTRUCTOR_PROOF_HASH='sha256:d4b55f38b99b0dc9cd4636786f8482f2c00c476a46b8c509129927ba709f3a96'
RAW_SPECIAL={'init':'source.lang.swift.decl.function.constructor','deinit':'source.lang.swift.decl.function.destructor','subscript':'source.lang.swift.decl.function.subscript','associatedtype':'source.lang.swift.decl.associatedtype','actor':'source.lang.swift.decl.class'}
PHYSICAL_GENERIC_COMPONENTS={('SwiftUI',line) for line in (22206,22211,25150,25155,27592)}|{('SwiftUICore',line) for line in (4043,13235,22684,24363,24370)}
TREE_FAMILIES={'func':{'Function'},'init':{'Allocator','Constructor'},'deinit':{'Destructor','Deallocator'},'var':{'Variable'},'let':{'Variable'},'subscript':{'Subscript'},'case':{'EnumElement','Function'},'typealias':{'TypeAlias'},'associatedtype':{'AssociatedType','AssociatedTypeRef'},'macro':{'Macro'}}

def digest(raw):return 'sha256:'+hashlib.sha256(raw if isinstance(raw,bytes) else raw.encode()).hexdigest()
def require(ok,why):
    if not ok:raise ValueError(why)
def pinned_module(path,expected,name):
    require(digest(path.read_bytes())==expected,'frozen dependency changed: '+name)
    spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);sys.modules[name]=module;spec.loader.exec_module(module);return module
helper=pinned_module(HELPER,HELPER_HASH,'public_ancestor_frozen_raw_parser')
NOMINAL_TREE_OWNERS=set(helper.NOMINAL)|{'TypeAlias'}
strict=pinned_module(STRICT,STRICT_HASH,'public_ancestor_frozen_strict_match')
destructor=pinned_module(DESTRUCTOR_FOLDER/'prove_access.py',DESTRUCTOR_GUARD_HASH,'public_ancestor_destructor_access')
swift16=pinned_module(SWIFT16_FOLDER/'exact_swift16.py',SWIFT16_GUARD_HASH,'public_ancestor_exact_swift16')
archived_swift16=pinned_module(SWIFT16_FOLDER/'archived_swift16.py',SWIFT16_WRAPPER_HASH,'public_ancestor_archived_swift16')
destructor_archive=pinned_module(DESTRUCTOR_FOLDER/'archive-wrapper-v2/archive_wrapper.py',DESTRUCTOR_WRAPPER_HASH,'public_ancestor_destructor_archive')
for file,sha in CLANG_SOURCE_HASHES.items():require(digest((CLANG_FOLDER/file).read_bytes())==sha,'Clang production source changed: '+file)
sys.path.insert(0,str(CLANG_FOLDER))
clang=pinned_module(CLANG_FOLDER/'exact_clang.py',CLANG_SOURCE_HASHES['exact_clang.py'],'exact_clang')

def archive_byte_reader():
    resolver=pinned_module(HERE/'archive-resolver-v1/archive_resolver.py',RESOLVER_HASH,'public_ancestor_archive_resolver')
    readers=[resolver.ArchiveResolver(manifest_path=resolver.V2_MANIFEST_PATH,expected_manifest_sha256=resolver.V2_MANIFEST_SHA256),resolver.ArchiveResolver()]
    def read(path,force_archive=False):
        require(type(force_archive) is bool,'archive mode must be strict boolean')
        semantic=str(path);matches=[r for r in readers if semantic in r._records]
        if matches:return matches[0].read_bytes(semantic,force_archive=force_archive)
        actual=Path(semantic)
        require(actual.is_absolute() and actual.is_relative_to(ROOT) and not actual.is_symlink(),'unbound external semantic input path')
        return actual.read_bytes()
    return read

def frozen_dependency_descriptors():
    bindings={'rawParser':(HELPER,HELPER_HASH),'strictRequestParser':(STRICT,STRICT_HASH),'lexicalParser':(HERE/'lexical_model_v2.py',LEXICAL_HASH),'swift16Guard':(SWIFT16_FOLDER/'exact_swift16.py',SWIFT16_GUARD_HASH),'swift16Wrapper':(SWIFT16_FOLDER/'archived_swift16.py',SWIFT16_WRAPPER_HASH),'swift16Manifest':(SWIFT16_FOLDER/'capture-inputs.json',SWIFT16_MANIFEST_HASH),'swift16Proof':(SWIFT16_FOLDER/'swift16-evidence.json',SWIFT16_PROOF_HASH),'clangManifest':(CLANG_FOLDER/'capture-inputs.json',CLANG_MANIFEST_HASH),'clangProof':(CLANG_FOLDER/'strict-clang-owner-proof.json',CLANG_PROOF_HASH),'destructorGuard':(DESTRUCTOR_FOLDER/'prove_access.py',DESTRUCTOR_GUARD_HASH),'destructorWrapper':(DESTRUCTOR_FOLDER/'archive-wrapper-v2/archive_wrapper.py',DESTRUCTOR_WRAPPER_HASH),'destructorProof':(DESTRUCTOR_FOLDER/'effective-access-evidence.json',DESTRUCTOR_PROOF_HASH),'graphReader':(GRAPH_ARCHIVE_FOLDER/'archive.py',GRAPH_READER_HASH),'graphArchive':(GRAPH_ARCHIVE_FOLDER/'archive-manifest.json',GRAPH_ARCHIVE_HASH),'externalArchiveResolver':(HERE/'archive-resolver-v1/archive_resolver.py',RESOLVER_HASH),'externalArchiveMappingV1':(HERE/'archive-inputs-v1/archive-input-mapping.json','sha256:57d10fa4184cd2585917ca721f94ac9270421ecfd4e2fcd187e0043bf5f49b75'),'externalArchiveMappingV2':(HERE/'archive-inputs-v2/archive-input-mapping.json','sha256:f1d53fde421d58b591c7e69eb35f3811db28785ca4cf15d244ba20b3cbd28dc8')}
    bindings.update({'clangSource:'+name:(CLANG_FOLDER/name,sha) for name,sha in CLANG_SOURCE_HASHES.items()})
    result={}
    for key,(path,sha) in bindings.items():
        require(digest(path.read_bytes())==sha,'frozen production dependency changed: '+key)
        result[key]={'path':str(path),'sha256':sha}
    return result

def actual_graph_closure(link,prefer_archive=False):
    with ExitStack() as cleanup:
        paths={d['path']:ROOT/d['path'] for d in link['rawGraphInputs']}
        if prefer_archive or any(not p.is_file() for p in paths.values()):
            archive=pinned_module(GRAPH_ARCHIVE_FOLDER/'archive.py',GRAPH_READER_HASH,'public_ancestor_raw_graph_archive')
            archive.INTERNAL_CACHE_ROOT.mkdir(parents=True,exist_ok=True)
            temporary=cleanup.enter_context(tempfile.TemporaryDirectory(dir=archive.INTERNAL_CACHE_ROOT))
            paths=archive.load_archive(GRAPH_ARCHIVE_FOLDER/'archive-manifest.json',expected_manifest_sha256=GRAPH_ARCHIVE_HASH.removeprefix('sha256:'),link_path=LINK,workspace_root=ROOT,scratch_root=Path(temporary)/'replay')
        usrs=set()
        for descriptor in link['rawGraphInputs']:
            with paths[descriptor['path']].open('rb') as stream,mmap.mmap(stream.fileno(),0,access=mmap.ACCESS_READ) as graph:
                require('sha256:'+hashlib.sha256(graph).hexdigest()==descriptor['sha256'],'actual immutable graph byte pin changed')
                usrs.update(match.group(1).decode() for match in re.finditer(rb'"precise"\s*:\s*"([^"\\]*)"',graph))
        closure=json.dumps(sorted(usrs),separators=(',',':'))
        require(len(usrs)==link['rawGraphUsrClosure']['rawGraphUsrCount'] and digest(closure)==link['rawGraphUsrClosure']['rawGraphUsrSetSha256'],'actual raw graph reconstructed USR closure mismatch')
        return closure+'\n'

def verify_destructor_dependency(read_bytes=None,force_archive=False):
    require(digest((DESTRUCTOR_FOLDER/'effective-access-evidence.json').read_bytes())==DESTRUCTOR_PROOF_HASH,'cleared destructor proof changed')
    result=destructor_archive.verify_all(read_bytes=read_bytes,force_archive=force_archive)
    require(result==json.loads((DESTRUCTOR_FOLDER/'effective-access-evidence.json').read_text()),'destructor complete independent replay mismatch')
    return result


@lru_cache(maxsize=4)
def structural_lines(source):return code_lines(source)

def declaration_column(source,record):
    if record['kind'] in {'init','deinit','subscript'}:return record['keywordOffset']+1
    text=structural_lines(source)[record['line']-1];start=record['keywordOffset']+len(record['kind'])
    matched=re.search(r'(?<![\w$])`?'+re.escape(record['name'])+r'`?(?![\w$])',text[start:])
    require(matched is not None,'actual source declaration token/column absent')
    return start+matched.start()+1

def norm(name):return name.strip('`').split('(',1)[0]
def active(record,selected):return all(str(x['branchLine']) in selected for x in record['conditions'])
def own_attributes(record):
    result=[]
    for line in [*record['attributes'],{'line':record['line'],'text':record['text']}]:
        text=line['text'];masked=code_lines(text)[0]
        cursor=0
        while cursor<len(text):
            match=re.search(r'@[A-Za-z_][A-Za-z0-9_.]*',masked[cursor:])
            if match is None:break
            start=cursor+match.start();end=cursor+match.end()
            if end<len(text) and masked[end]=='(':
                depth=0
                while end<len(text):
                    depth+=(masked[end]=='(')-(masked[end]==')');end+=1
                    if depth==0:break
                require(depth==0,'unterminated declaration-bound attribute')
            result.append({'line':line['line'],'text':text[start:end]});cursor=end
    return result


def nominal_identity(node):
    require(node['kind'] in NOMINAL_TREE_OWNERS,'not nominal tree')
    names=[n for n in node['children'] if n['kind']=='Identifier']
    owners=[n for n in node['children'] if n['kind'] in NOMINAL_TREE_OWNERS or n['kind'] in {'Module','Extension'}]
    require(len(names)==len(owners)==1 and len(node['children'])==2,'ambiguous nominal tree')
    owner=owners[0]
    if owner['kind']=='Module':return owner['text'],[names[0]['text']]
    if owner['kind']=='Extension':
        modules=[n for n in owner['children'] if n['kind']=='Module']
        nominals=[n for n in owner['children'] if n['kind'] in NOMINAL_TREE_OWNERS]
        require(len(modules)==len(nominals)==1 and all(n['kind'] in NOMINAL_TREE_OWNERS or n['kind'] in {'Module','DependentGenericSignature'} for n in owner['children']),'ambiguous nominal extension parent')
        namespace,path=nominal_identity(nominals[0]);return modules[0]['text'],path+[names[0]['text']]
    namespace,path=nominal_identity(owner);return namespace,path+[names[0]['text']]


def extension_context(node):
    while node['kind'] in NOMINAL_TREE_OWNERS:
        owners=[n for n in node['children'] if n['kind'] in NOMINAL_TREE_OWNERS or n['kind'] in {'Module','Extension'}]
        require(len(owners)==1,'ambiguous nominal extension context');node=owners[0]
    if node['kind']!='Extension':return None
    modules=[n for n in node['children'] if n['kind']=='Module'];nominals=[n for n in node['children'] if n['kind'] in NOMINAL_TREE_OWNERS]
    require(len(modules)==len(nominals)==1,'ambiguous full extension context')
    namespace,path=nominal_identity(nominals[0]);return {'extensionModule':modules[0]['text'],'nominalNamespace':namespace,'nominalPath':path}


def declaration_tree(tree,kind,name):
    children=tree['children']
    if len(children)==1 and children[0]['kind']=='Static':children=children[0]['children']
    require(len(children)==1,'ambiguous direct declaration tree')
    node=children[0]
    if kind in NOMINAL:
        require(node['kind'] in helper.NOMINAL and (helper.NOMINAL[node['kind']]==kind or (kind=='actor' and node['kind']=='Class')),'wrong nominal tree family')
        module,path=nominal_identity(node);require(path[-1]==name,'wrong nominal tree name');return module,path[:-1],node
    require(node['kind'] in TREE_FAMILIES.get(kind,set()),'unsupported/wrong declaration tree family')
    names=[x for x in node['children'] if x['kind'] in {'Identifier','InfixOperator','PrefixOperator','PostfixOperator'}]
    if kind not in {'init','deinit','subscript'}:require(len(names)==1 and names[0]['text']==name,'wrong direct declaration tree name')
    owners=[x for x in node['children'] if x['kind'] in NOMINAL_TREE_OWNERS or x['kind'] in {'Extension','Module'}]
    require(len(owners)==1,'ambiguous full declaration tree owner')
    owner=owners[0]
    if owner['kind']=='Module':return owner['text'],[],node
    if owner['kind']=='Extension':
        nominal=[x for x in owner['children'] if x['kind'] in NOMINAL_TREE_OWNERS]
        modules=[x for x in owner['children'] if x['kind']=='Module']
        require(len(nominal)==len(modules)==1,'ambiguous direct extension tree')
        owner=nominal[0]
    module,path=nominal_identity(owner);return module,path,node


class Validator:
    def read_input_bytes(self,path):
        reader=getattr(self,'archive_reader',None)
        return reader(str(path),force_archive=getattr(self,'prefer_archive',False)) if reader else Path(path).read_bytes()

    def verify_driver_bytes(self):
        require(digest(self.read_input_bytes(self.link['toolchainEvidence']['compiler']['driverPath']))==self.tool_pins['compiler']['sha256'],'actual compiler driver executable byte binding changed')

    def __init__(self):
        require(digest((HERE/'lexical_model_v2.py').read_bytes())==LEXICAL_HASH,'frozen lexical parser changed')
        require(digest(V12.read_bytes())==V12_HASH and digest(LINK.read_bytes())==LINK_HASH,'immutable v12/836 changed')
        self.v12=json.loads(V12.read_text());self.link=json.loads(LINK.read_text());self.inputs={};self.pins={};self.paths={}
        def pin(key,path,expected):
            path=Path(path);path=path if path.is_absolute() else ROOT/path
            data=path.read_bytes();require(digest(data)==expected,'actual pinned input changed: '+key)
            self.inputs[key]=data.decode();self.pins[key]=expected;self.paths[key]=str(path)
        pin('v12',V12,V12_HASH);pin('immutable836',LINK,LINK_HASH);pin('projectedDuplicateProof',DUPLICATE_PROOF,DUPLICATE_PROOF_HASH)
        for interface in self.link['interfaces']:
            module=interface['module']
            for label,path_field,hash_field in [('source','path','sha256'),('index','indexOutput','indexOutputSha256'),('request','indexRequest','indexRequestSha256')]:pin(module+':'+label,interface[path_field],interface[hash_field])
        for label in ('index','request'):
            self.inputs['SwiftUICore:lineage'+label.title()]=self.inputs['SwiftUICore:'+label];self.pins['SwiftUICore:lineage'+label.title()]=self.pins['SwiftUICore:'+label];self.paths['SwiftUICore:lineage'+label.title()]=self.paths['SwiftUICore:'+label]
        for label,(name,sha) in CORE_PINS.items():pin('SwiftUICore:'+label,CORE_FOLDER/name,sha)
        for number,(name,sha) in enumerate(EXTERNAL_PROOFS):
            pin('externalProof:'+str(number),HERE/name,sha)
            for record in json.loads(self.inputs['externalProof:'+str(number)])['modules']:
                module=record['module'];require(module in EXTERNAL_TARGETS,'external module outside bounded allowlist')
                for label,descriptor in [('source',record['source']),('index',record['process']['stdout']),('request',record['request'])]:pin('external:'+module+':'+label,descriptor['path'],descriptor['sha256'])
        pin('foreignProof',FOREIGN_FOLDER/'process-evidence-v2.json',FOREIGN_PROOF_HASH)
        for module,sha in FOREIGN_RECEIPT_HASHES.items():
            key='external:'+module+':receipt';pin(key,FOREIGN_FOLDER/'receipts'/(module+'.receipt.json'),sha)
            record=json.loads(self.inputs[key])
            for label,descriptor in [('source',record['source']),('index',record['process']['stdout']),('request',record['request']),('stderr',record['process']['stderr'])]:pin('external:'+module+':'+label,descriptor['path'],descriptor['sha256'])
        self.swift16=archived_swift16.ArchivedExactSwift16()
        require(self.swift16.validate()==json.loads((SWIFT16_FOLDER/'swift16-evidence.json').read_text())['witnesses'],'Swift16 complete independent reconstruction differs')
        pin('swift16Proof',SWIFT16_FOLDER/'swift16-evidence.json',SWIFT16_PROOF_HASH);pin('swift16Manifest',SWIFT16_FOLDER/'capture-inputs.json',SWIFT16_MANIFEST_HASH)
        for key,path in self.swift16.paths.items():
            if key not in {'source','headerIndex','headerRequest'} and not key.startswith('tool:'):pin('swift16:'+key,path,self.swift16.pins[key])
        self.clang=clang.ExactClangOwners()
        require(self.clang.validate()==json.loads((CLANG_FOLDER/'strict-clang-owner-proof.json').read_text())['requestedOwners'],'Clang complete independent reconstruction differs')
        pin('clangProof',CLANG_FOLDER/'strict-clang-owner-proof.json',CLANG_PROOF_HASH);pin('clangManifest',CLANG_FOLDER/'capture-inputs.json',CLANG_MANIFEST_HASH)
        for key,path in self.clang.paths.items():
            if not key.startswith('tool:') and not key.startswith('stdout:clang-'):pin('clang:'+key,path,self.clang.pins[key])
        verify_destructor_dependency()
        pin('destructorProof',DESTRUCTOR_FOLDER/'effective-access-evidence.json',DESTRUCTOR_PROOF_HASH)
        for module in ('SwiftUI','SwiftUICore'):
            path=destructor.raw_path(destructor.RAW/(module+'-arm64.stdout'))
            pin(module+':destructorAST',path,digest(path.read_bytes()))
        self.tool_pins={}
        for name in ('compiler','sourcekitd','sourcekitLsp'):
            record=self.link['toolchainEvidence'][name];path=Path(record.get('executablePath',record.get('path')))
            require(digest(path.read_bytes())==record['sha256'],'actual compiler tool changed: '+name)
            self.tool_pins[name]={'path':str(path),'sha256':record['sha256']}
        require(digest(helper.DEMANGLE.read_bytes())==DEMANGLE_HASH,'frozen demangler changed')
        self.tool_pins['demangler']={'path':str(helper.DEMANGLE),'sha256':DEMANGLE_HASH}
        self.verify_driver_bytes()
        self.inputs['graphUsrClosure']=actual_graph_closure(self.link);self.pins['graphUsrClosure']=digest(self.inputs['graphUsrClosure'])
        self.capture_actual()
        self.inputs=MappingProxyType(self.inputs);self.pins=MappingProxyType(self.pins)

    def source_compilerargs(self,module,source,source_path):
        if module=='SwiftUI':return [source_path,'-sdk',self.link['toolchainEvidence']['sdk'],'-target',self.link['toolchainEvidence']['target'],'-module-name',module]
        rows=[line for line in source.splitlines() if line.startswith('// swift-module-flags: ') or line.startswith('// swift-module-flags-ignorable: ')]
        require(len(rows)==2,'complete SDK header compiler flags')
        flags=[arg for row in rows for arg in shlex.split(row.split(': ',1)[1])];result=[source_path];i=0
        while i<len(flags):
            arg=flags[i]
            if arg in {'-target','-target-variant','-target-arch-variant'}:i+=2;continue
            if arg=='-target-min-inlining-version':
                result+=['-Xfrontend',arg,'-Xfrontend',flags[i+1]];i+=2;continue
            if arg in {'-enable-objc-interop','-formal-cxx-interoperability-mode=off','-parse-stdlib','-enforce-exclusivity=unchecked','-disable-objc-attr-requires-foundation-module','-enable-lexical-lifetimes=false','-strict-memory-safety','-enable-experimental-concurrency'}:result+=['-Xfrontend',arg]
            else:result.append(arg)
            i+=1
        result+=['-sdk',self.link['toolchainEvidence']['sdk'],'-target',self.link['toolchainEvidence']['target']]
        require(result.count('-module-name')==1 and result[result.index('-module-name')+1]==module,'exact source header module binding')
        if module=='SwiftUICore':require(result.count('-module-abi-name')==1 and result[result.index('-module-abi-name')+1]=='SwiftUI','exact Core source ABI/header binding')
        return result

    def external_modules(self,raw):
        result=[]
        for number,(name,sha) in enumerate(EXTERNAL_PROOFS):
            key='externalProof:'+str(number);require(digest(raw[key])==sha,'bounded external capture manifest changed')
            document=json.loads(raw[key])
            require(document['target']==self.link['toolchainEvidence']['target'] and document['sdk']==self.link['toolchainEvidence']['sdk'],'external target/SDK capture binding')
            require(document['immutableLink']=={'path':str(LINK.relative_to(ROOT)),'sha256':LINK_HASH},'external immutable source lineage')
            require(len(document['modules'])==2 and {r['module'] for r in document['modules']}=={'Swift','Foundation'},'external primary module cardinality')
            require(set(document['toolchain'])=={'swiftc','sourcekitLsp','sourcekitd'},'external primary compiler tool cardinality')
            for name,tool in document['toolchain'].items():
                expected=self.link['toolchainEvidence'][{'swiftc':'compiler'}.get(name,name)]
                require(tool['sha256']==expected['sha256'] and digest(self.read_input_bytes(tool['path']))==expected['sha256'],'external primary exact actual tool byte identity')
            for record in document['modules']:
                module=record['module'];require(module in EXTERNAL_TARGETS and module not in [r['module'] for r in result],'external module allowlist/cardinality')
                source=raw['external:'+module+':source'];request=raw['external:'+module+':request']
                require(strict.request_identity_matches(request,interface=record['source']['path'],sdk=document['sdk'],target=document['target'],module=module),'external exact compiler request scalar identity')
                require(strict.parse_compilerargs(request)==self.source_compilerargs(module,source,record['source']['path']),'external complete source/header compiler options')
                process=record['process'];require(type(process['exit']) is int and process['exit']==0 and process['stdout']['sha256']==self.pins['external:'+module+':index'] and record['request']['sha256']==self.pins['external:'+module+':request'],'external successful captured process streams')
                require(process['argv']==['xcrun','sourcekit-lsp','debug','run-sourcekitd-request','--request-file',str(ROOT/record['request']['path'])] and process['cwd']==str(ROOT),'external actual compiler invocation')
                require(record['source']['sha256']==self.pins['external:'+module+':source'] and record['source']['path']==self.paths['external:'+module+':source'],'external primary exact source descriptor')
                require(type(record['request']['bytes']) is int and record['request']['bytes']==len(request.encode()),'external primary exact request bytes')
                require(type(process['stdout']['bytes']) is int and process['stdout']['bytes']==len(raw['external:'+module+':index'].encode()) and process['stderr']['bytes']==0 and process['stderr']['sha256']==digest(''),'external primary actual stream descriptors')
                result.append(record)
        document=json.loads(raw['foreignProof'])
        require(document['immutableLink']=={'path':str(LINK.relative_to(ROOT)),'sha256':LINK_HASH} and document['sdk']==self.link['toolchainEvidence']['sdk'] and document['target']==self.link['toolchainEvidence']['target'],'foreign exact source/target/link manifest')
        modules=[r['module'] for r in document['modules']]
        require(len(modules)==len(set(modules)) and set(modules)==set(FOREIGN_RECEIPT_HASHES),'foreign exact module cardinality/allowlist')
        require(all(r['receipt']==str((FOREIGN_FOLDER/'receipts'/(r['module']+'.receipt.json')).relative_to(ROOT)) for r in document['modules']),'foreign exact receipt descriptor path')
        for module in modules:
            record=json.loads(raw['external:'+module+':receipt']);process=record['process']
            require(record['module']==module and module not in [r['module'] for r in result],'foreign receipt exact module binding')
            source=raw['external:'+module+':source'];request=raw['external:'+module+':request']
            require(strict.request_identity_matches(request,interface=record['source']['path'],sdk=document['sdk'],target=document['target'],module=module) and strict.parse_compilerargs(request)==self.source_compilerargs(module,source,record['source']['path']),'foreign complete compiler header/source request')
            require(type(process['returncode']) is int and process['returncode']==0 and raw['external:'+module+':stderr']=='','foreign genuine process returncode/stderr')
            require(process['argv']==['xcrun','sourcekit-lsp','debug','run-sourcekitd-request','--request-file',str(FOREIGN_FOLDER/'requests'/(module+'.yaml'))] and process['cwd']==str(ROOT),'foreign exact actual process invocation')
            require(type(process['startedAtEpochNs']) is int and type(process['finishedAtEpochNs']) is int and 0<process['startedAtEpochNs']<process['finishedAtEpochNs'],'foreign actual process epoch types/order')
            from datetime import datetime,timezone
            for name,epoch in [('startedAt','startedAtEpochNs'),('finishedAt','finishedAtEpochNs')]:
                require(type(process[name]) is str and re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z',process[name]),'foreign actual process timestamp shape')
                timestamp=datetime.fromisoformat(process[name].replace('Z','+00:00'));seconds=int(timestamp.timestamp());expected=seconds*1000000000+timestamp.microsecond*1000
                require(expected==process[epoch],'foreign actual process timestamp/epoch equality')
            for label,descriptor in [('source',record['source']),('request',record['request']),('index',process['stdout']),('stderr',process['stderr'])]:
                require(type(descriptor['bytes']) is int and descriptor['bytes']>=0 and descriptor['path']==self.paths['external:'+module+':'+label] and descriptor['sha256']==self.pins['external:'+module+':'+label] and len(raw['external:'+module+':'+label].encode())==descriptor['bytes'],'foreign actual stream/source descriptor binding')
            for name,tool in record['toolchain'].items():
                require(name in {'xcrun','sourcekitLsp','sourcekitd','swiftc'} and type(tool['bytes']) is int and tool['bytes']>0 and digest(self.read_input_bytes(tool['path']))==tool['sha256'] and len(self.read_input_bytes(tool['path']))==tool['bytes'],'foreign actual compiler tool bytes')
                expected=self.link['toolchainEvidence'].get({'swiftc':'compiler'}.get(name,name))
                if expected:require(tool['sha256']==expected['sha256'] and tool['path'] in {expected.get('executablePath',expected.get('path')),expected.get('driverPath')},'foreign immutable compiler tool semantic path/byte pin')
                else:require(name=='xcrun' and tool['path']=='/usr/bin/xcrun' and tool['sha256']=='sha256:bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9','foreign actual xcrun tool identity')
            require(set(record['toolchain'])=={'xcrun','sourcekitLsp','sourcekitd','swiftc'},'foreign compiler tool cardinality')
            result.append(record)
        require(digest(raw['foreignProof'])==FOREIGN_PROOF_HASH,'foreign immutable capture manifest pin')
        return result

    def swift16_correspondences(self,raw):
        require(digest(raw['swift16Proof'])==SWIFT16_PROOF_HASH and digest(raw['swift16Manifest'])==SWIFT16_MANIFEST_HASH,'cleared real Swift16 capture changed')
        aliases={'source':'external:Swift:source','headerIndex':'external:Swift:index','headerRequest':'external:Swift:request'}
        inputs={key:raw[aliases.get(key,'swift16:'+key)].encode() for key in self.swift16.inputs if aliases.get(key,'swift16:'+key) in raw}
        result=self.swift16.validate(inputs)
        require(result==json.loads(raw['swift16Proof'])['witnesses'],'Swift16 independent production rows mismatch')
        return {r['name']:r for r in result}

    def clang_nominals(self,raw):
        require(hasattr(self,'clang'),'bounded Clang production dependency absent')
        require(digest(raw['clangProof'])==CLANG_PROOF_HASH and digest(raw['clangManifest'])==CLANG_MANIFEST_HASH,'cleared Clang capture changed')
        overrides={key:raw['clang:'+key].encode() for key in self.clang.inputs if 'clang:'+key in raw}
        rows=self.clang.validate_overrides(overrides)
        expected={'AppKit.NSWindow','AppKit.NSApplication','AppKit.NSColor','AppKit.NSControl.ControlSize','AppKit.NSDirectionalEdgeInsets','AppKit.NSUnderlineStyle','AppKit.NSAnimationContext','Foundation.NSUserActivity','CoreFoundation.CGPoint','CoreFoundation.CGSize','CoreFoundation.CGRect','Spatial.Size3D'}
        require(len(rows)==12 and {r['target'] for r in rows}==expected,'exact bounded Clang owner target closure')
        supports=self.clang.supportRows
        require(len(supports)==1 and supports[0]['target']=='AppKit.NSControl','exact Clang qualification support closure')
        result=[]
        for row in rows:
            qualified=row['target'].split('.')
            require(row['compiledNamespace']=='__C' and row['compiledKind'] in NOMINAL_TREE_OWNERS,'exact compiled C nominal namespace/family')
            namespace,path=nominal_identity(row['nominalTree'])
            require(namespace==row['compiledNamespace'] and path==row['compiledPath'] and row['nominalTree']['kind']==row['compiledKind'],'exact captured C full nominal tree')
            export=row['moduleExport']
            require(export['module']==row['physicalModule']==qualified[0] and export['directExport']=='*' and export['umbrella']==qualified[0]+'.h' and export['header']==Path(row['sourcePath']).name and export['header'] not in export['excludedHeaders'],'exact C public header export ancestry')
            chain=[]
            for witness in ([supports[0]] if row['target']=='AppKit.NSControl.ControlSize' else [])+[row]:
                chain.append({'module':witness['physicalModule'],'line':witness['ast']['definitionPosition']['line'],'name':witness['compiledPath'][-1],'kind':witness['compiledKind'],'access':'public','sourceLanguage':'Clang','accessRule':'exact exported physical declaration reached by successful ordinary external Swift import at pinned target','text':witness['sourceText'],'attributes':[],'conditions':witness['sourceConditionFrames'],'physicalSourcePath':witness['sourcePath'],'physicalSourceSha256':witness['sourceHash'],'compiledImportProof':witness})
            result.append({'sourceModule':qualified[0],'sourceTargetPath':qualified[1:],'namespace':namespace,'namespaces':[namespace],'originAttributes':[],'path':path,'nominalUsr':row['canonicalUsr'],'nominalTree':row['nominalTree'],'chain':chain,'canonicalImportCorrespondence':row})
        return result

    def external_nominals(self,raw,trees):
        result=[];swift_correspondences=self.swift16_correspondences(raw)
        for record in self.external_modules(raw):
            module=record['module'];source=raw['external:'+module+':source'];scope_records=external_scopes(source,module);scopes={s['line']:s for s in scope_records};entities=helper.entities(raw['external:'+module+':index'])
            by_position=defaultdict(list)
            for entity in entities:by_position[(entity['line'],entity['column'])].append(entity)
            for target in sorted(EXTERNAL_TARGETS[module]):
                matches=[]
                for scope in scope_records:
                    if scope['kind'] not in NOMINAL or scope['scopeLines'] or scope['path']!=target.split('.'):continue
                    records=by_position[(scope['line'],declaration_column(source,scope))]
                    if not records:continue
                    require(len(records)==1 and not records[0].get('is_implicit'),'external nominal raw physical cardinality')
                    entity=records[0]
                    require(norm(entity['name'])==scope['name'] and entity['kind']=='source.lang.swift.decl.'+('class' if scope['kind']=='actor' else scope['kind']),'external nominal exact source/raw family/name')
                    require(entity.get('effective_access','').rsplit('.',1)[-1] in PUBLIC and scope['explicitAccess'] in PUBLIC,'external nominal source/compiler public access')
                    require(not scope['conditions'],'external nominal branch requires independent compiler selection')
                    require(entity['usr'] in trees,'external exact nominal tree absent')
                    namespace,path,node=declaration_tree(trees[entity['usr']],scope['kind'],scope['name'])
                    require(path+[scope['name']]==target.split('.') and extension_context(node) is None,'external exact full nominal path')
                    canonical_usr=entity['usr'];correspondence=None
                    if module=='Swift':
                        correspondence=swift_correspondences[target]
                        require(namespace=='main' and correspondence['sourceUsr']==entity['usr'] and correspondence['line']==scope['line'] and correspondence['column']==entity['column'] and correspondence['kind']==scope['kind'],'exact Swift physical source/index correspondence')
                        canonical_usr=correspondence['canonicalUsr'];require(canonical_usr in trees,'exact imported Swift nominal full tree absent')
                        namespace,canonical_path,canonical_node=declaration_tree(trees[canonical_usr],scope['kind'],scope['name'])
                        require(namespace=='Swift' and canonical_path==path and extension_context(canonical_node) is None,'exact Swift canonical imported full nominal tree')
                    else:require(namespace==module,'external exact nominal namespace')
                    physical=[scopes[line] for line in scope['scopeLines']]
                    require(len(entity['sourcekitContext'])==len(physical) and all(c['line']==s['line'] and norm(c['name'])==s['name'] for c,s in zip(entity['sourcekitContext'],physical)),'external raw full physical ancestry')
                    chain=[]
                    for ancestor in [*physical,scope]:
                        require(ancestor['kind'] in NOMINAL and ancestor['explicitAccess'] in PUBLIC,'external lexical ancestor public access')
                        chain.append({'module':module,'line':ancestor['line'],'name':ancestor['name'],'kind':ancestor['kind'],'access':ancestor['explicitAccess'],'text':ancestor['text'],'attributes':own_attributes(ancestor),'conditions':ancestor['conditions'],'compilerSelectedSourceRecord':True})
                    origin_attributes=[a for a in own_attributes(scope) if a['text'].startswith('@_originallyDefinedIn')]
                    origins=[]
                    for attribute in origin_attributes:
                        match=re.fullmatch(r'@_originallyDefinedIn\(module: "(\w+)", (macOS|macCatalyst|iOS|tvOS|watchOS|visionOS) ([0-9]+(?:\.[0-9]+)*)\)',attribute['text'])
                        require(match is not None,'external own originally-defined annotation shape')
                        origins.append(match.groups())
                    require(len(origins)==len(set((o[0],o[1]) for o in origins)) and len({o[0] for o in origins if o[1]=='macOS'})<=1,'external own originally-defined annotation cardinality')
                    namespaces=sorted({namespace}|{o[0] for o in origins if o[1]=='macOS'})
                    matches.append({'sourceModule':module,'namespace':namespace,'namespaces':namespaces,'originAttributes':origin_attributes,'path':path+[scope['name']],'nominalUsr':canonical_usr,'nominalTree':trees[canonical_usr]['children'][0],'sourceNominalUsr':entity['usr'],'canonicalImportCorrespondence':correspondence,'chain':chain,'sourceRawEntity':entity})
                require(len(matches)==1,'external nominal active source/raw resolution cardinality')
                result.append(matches[0])
        result.extend(self.clang_nominals(raw))
        return result

    def source_namespace(self,module,source):
        if module!='SwiftUICore':return module
        args=self.source_compilerargs(module,source,'unused-source-path')
        return args[args.index('-module-abi-name')+1]

    def destructor_access(self,raw,module,declaration,nodes):
        line=declaration['line'];interface=next(i for i in self.link['interfaces'] if i['module']==module)
        matches=[n for n in nodes if n['line']==line and n['source']==interface['path']]
        require(len(matches)==1,'destructor actual AST cardinality')
        node=matches[0];text=raw[module+':source'].splitlines()[line-1]
        require(node['kind']=='destructor_decl' and node['name']=='deinit' and node['access'] in {'public','open','private','fileprivate','internal','package'},'destructor AST access/family')
        require(node['column']==len(text[:text.index('deinit')])+1 and node['endLine']==line and node['endColumn']==node['column'] and 'interface_type=' in node['raw'] and '<error' not in node['raw'],'destructor typed physical source position')
        require([n['line'] for n in node['owners']]==declaration['scopeLines'],'destructor full physical AST ancestry')
        source_model=model(raw[module+':source'],module);scopes={s['line']:s for s in source_model['scopes']}
        for owner in node['owners']:
            scope=scopes[owner['line']]
            require(owner['source']==interface['path'] and owner['line']<=line<=owner['endLine'] and owner['name']==scope['name'].split('.')[-1] and owner['kind']==('class_decl' if scope['kind']=='actor' else scope['kind']+'_decl'),'destructor AST/source owner identity')
        return node['access']

    def probe_source(self,module,source):
        parts=[]
        for number,line in enumerate(source.splitlines(),1):
            text=line.strip()
            if re.match(r'^#(?:if |elseif |else$|endif$)',text):
                parts.append(text)
                if text!='#endif':parts.append('print("'+module+':'+str(number)+'")')
        return '\n'.join(parts)+'\n'

    def capture_actual(self):
        SCRATCH.mkdir(parents=True,exist_ok=True)
        require(str(SCRATCH.resolve()).startswith('/Users/adrdsouza/Library/Caches/'),'noninternal scratch rejected')
        records={}
        def capture(argv):
            process=subprocess.run(argv,cwd=SCRATCH,capture_output=True,check=False)
            return {'argv':argv,'cwd':str(SCRATCH),'exitCode':process.returncode,'stdout':process.stdout.decode(),'stderr':process.stderr.decode()}
        compiler=self.link['toolchainEvidence']['compiler']['driverPath']
        for interface in self.link['interfaces']:
            module=interface['module'];source=self.probe_source(module,self.inputs[module+':source'])
            probe=SCRATCH/(module+'-branch-probe.swift');binary=SCRATCH/(module+'-branch-probe');probe.write_text(source)
            argv=[compiler,*self.source_compilerargs(module,self.inputs[module+':source'],str(probe)),'-module-cache-path',str(SCRATCH/'module-cache'),'-o',str(binary)]
            compiled=capture(argv);require(compiled['exitCode']==0,'actual branch probe compilation failed: '+compiled['stderr'])
            executed=capture([str(binary)]);require(executed['exitCode']==0,'actual branch probe runtime failed')
            records[module]={'compile':compiled,'run':executed};self.inputs[module+':probeSource']=probe.read_text()
        external_usrs={e['usr'] for record in self.external_modules(self.inputs) for e in helper.entities(self.inputs['external:'+record['module']+':index']) if e['kind'] in {'source.lang.swift.decl.'+k for k in NOMINAL} and not e.get('is_implicit') and e['usr'].startswith('s:')}
        external_usrs|={r['canonicalUsr'] for r in self.swift16_correspondences(self.inputs).values()}
        usrs=sorted(external_usrs|{e['usr'] for interface in self.link['interfaces'] for e in helper.entities(self.inputs[interface['module']+':index']) if e['usr'].startswith('s:') and not e['usr'].startswith('s:e:') and not e.get('is_implicit')})
        expanded=[];batches=[]
        for start in range(0,len(usrs),300):
            group=usrs[start:start+300];argv=[str(helper.DEMANGLE),'--expand',*['$s'+u[2:] for u in group]]
            captured=capture(argv);require(captured['exitCode']==0 and not captured['stderr'],'actual demangler failed')
            expanded.append(captured['stdout']);batches.append({'argv':argv,'cwd':captured['cwd'],'exitCode':captured['exitCode'],'stdoutSha256':digest(captured['stdout']),'stderr':captured['stderr']})
        records['demangle']=batches
        self.inputs['processResults']=json.dumps(records,sort_keys=True,separators=(',',':'))+'\n'
        self.inputs['trees']=''.join(expanded);self.actual_processes=self.inputs['processResults'];self.actual_trees=self.inputs['trees'];self.tree_usrs=usrs
        for key in ('processResults','trees',*[i['module']+':probeSource' for i in self.link['interfaces']]):self.pins[key]=digest(self.inputs[key])

    def validate(self,raw=None,_expected=None):
        require(digest((HERE/'lexical_model_v2.py').read_bytes())==LEXICAL_HASH,'frozen lexical parser changed')
        raw=self.inputs if raw is None else raw
        require(raw['processResults']==self.actual_processes,'process output differs from actual captured subprocesses')
        processes=json.loads(raw['processResults']);selected={}
        self.verify_driver_bytes()
        for interface in self.link['interfaces']:
            module=interface['module']
            require(raw[module+':probeSource']==self.probe_source(module,raw[module+':source']),'full SDK conditional/probe binding mismatch')
            expected_argv=[self.link['toolchainEvidence']['compiler']['driverPath'],*self.source_compilerargs(module,raw[module+':source'],str(SCRATCH/(module+'-branch-probe.swift'))),'-module-cache-path',str(SCRATCH/'module-cache'),'-o',str(SCRATCH/(module+'-branch-probe'))]
            require(processes[module]['compile']['argv']==expected_argv and processes[module]['compile']['cwd']==str(SCRATCH) and processes[module]['run']['argv']==[str(SCRATCH/(module+'-branch-probe'))] and processes[module]['run']['cwd']==str(SCRATCH),'exact actual SDK header/target branch invocation')
            require(type(processes[module]['compile']['exitCode']) is int and processes[module]['compile']['exitCode']==0 and processes[module]['compile']['stdout']==processes[module]['compile']['stderr']=='','actual compiler failed/output mismatch')
            require(type(processes[module]['run']['exitCode']) is int and processes[module]['run']['exitCode']==0 and not processes[module]['run']['stderr'],'actual branch probe runtime failed')
            lines=processes[module]['run']['stdout'].splitlines();require(len(lines)==len(set(lines)) and all(re.fullmatch(re.escape(module)+r':\d+',x) for x in lines),'actual selected branch output/cardinality malformed')
            selected[module]=[x.split(':')[1] for x in lines]
        require(set(helper.trees(raw['trees']))==set(self.tree_usrs),'actual tree USR closure changed')
        for name,descriptor in self.tool_pins.items():require(digest(self.read_input_bytes(descriptor['path']))==descriptor['sha256'],'actual frozen tool changed: '+name)
        result=self._reconstruct(raw,selected,raw['trees'])
        if _expected is not None:require(result==_expected,'independent actual-input reconstruction differs from accepted artifact')
        require(digest(raw['trees'])==digest(self.actual_trees),'actual captured tree bytes changed')
        for key,expected in self.pins.items():require(digest(raw[key])==expected,'actual raw provenance pin mismatch: '+key)
        return result

    def accept(self,candidate,raw=None):
        return self.validate(raw,_expected=candidate)

    def _reconstruct(self,raw,selected,tree_text):
        """Internal reconstruction; validate/accept apply complete provenance gates."""
        require(raw['processResults']==self.actual_processes,'internal process binding changed')
        actual_selected={module:[line.split(':')[1] for line in json.loads(self.actual_processes)[module]['run']['stdout'].splitlines()] for module in ('SwiftUI','SwiftUICore')}
        require(selected==actual_selected and tree_text==raw['trees'],'caller branch/tree map rejected')
        require(set(raw)==set(self.inputs),'raw input closure changed')
        require(digest(raw['v12'])==V12_HASH and digest(raw['immutable836'])==LINK_HASH,'immutable lineage changed')
        trees=helper.trees(tree_text)
        graph_usrs=json.loads(raw['graphUsrClosure'])
        require(graph_usrs==sorted(set(graph_usrs)) and len(graph_usrs)==self.link['rawGraphUsrClosure']['rawGraphUsrCount'] and digest(json.dumps(graph_usrs,separators=(',',':')))==self.link['rawGraphUsrClosure']['rawGraphUsrSetSha256'],'immutable actual graph USR closure changed')
        graph_usrs=set(graph_usrs)
        require(digest(raw['destructorProof'])==DESTRUCTOR_PROOF_HASH,'cleared destructor proof input changed')
        destructor_nodes={module:destructor.parse_ast(raw[module+':destructorAST'],module) for module in ('SwiftUI','SwiftUICore')}
        parsed={};entities={};by_line={};scopes={};selected_by_module={};nominals=[];held_nominals={}
        for interface in self.link['interfaces']:
            module=interface['module'];source=raw[module+':source'];parsed[module]=model(source,module)
            require(strict.request_identity_matches(raw[module+':request'],interface=interface['path'],sdk=self.link['toolchainEvidence']['sdk'],target=self.link['toolchainEvidence']['target'],module=module),'exact module request binding changed')
            require(strict.parse_compilerargs(raw[module+':request'])==self.source_compilerargs(module,source,interface['path']),'extra/missing compiler request/header options')
            if module=='SwiftUICore':
                receipt=json.loads(raw[module+':indexReceipt'])
                require(digest(raw[module+':indexReceipt'])==CORE_PINS['indexReceipt'][1] and receipt['sourcekit']['exit']==0 and receipt['sourceSha256']==interface['sha256'] and receipt['source']==interface['path'],'actual successful Core header-index process binding')
                require(receipt['request']['sha256']==CORE_PINS['request'][1] and receipt['sourcekit']['stdout']['sha256']==CORE_PINS['index'][1],'Core actual raw process/request streams binding')
                require(digest(raw[module+':lineageIndex'])==interface['indexOutputSha256'] and digest(raw[module+':lineageRequest'])==interface['indexRequestSha256'],'immutable836 textual Core lineage changed')
            entities[module]=helper.entities(raw[module+':index']);by_line[module]=defaultdict(list)
            require(len(entities[module])=={'SwiftUI':10679,'SwiftUICore':8506}[module],'exact observed compiler declaration-record denominator')
            for entity in entities[module]:by_line[module][entity['line']].append(entity)
            scopes[module]={s['line']:s for s in parsed[module]['scopes']}
            selected_by_module[module]=set(selected[module])
            require(selected_by_module[module]<=set(str(b['line']) for f in parsed[module]['frames'].values() for b in f['branches']),'selected branch outside actual source')
            for scope in parsed[module]['scopes']:
                if scope['kind'] not in NOMINAL or not active(scope,selected_by_module[module]):continue
                matches=[e for e in by_line[module][scope['line']] if e['column']==declaration_column(source,scope)]
                try:
                    require(len(matches)==1 and not matches[0].get('is_implicit'),'nominal raw identity/cardinality')
                    entity=matches[0];require(norm(entity['name'])==scope['name'] and entity['kind']=='source.lang.swift.decl.'+('class' if scope['kind']=='actor' else scope['kind']),'nominal exact raw name/kind')
                    require(entity['usr'] in trees,'nominal tree absent')
                    namespace,owner,nominal_node=declaration_tree(trees[entity['usr']],scope['kind'],scope['name'])
                    tree_extension=extension_context(nominal_node)
                    require(tree_extension is None or tree_extension['extensionModule']==self.source_namespace(module,source),'nominal extension module disagrees with actual source module')
                    lexical=[scopes[module][n]['name'] for n in scope['scopeLines'] if scopes[module][n]['kind'] in NOMINAL]
                    extensions=[scopes[module][n] for n in scope['scopeLines'] if scopes[module][n]['kind']=='extension']
                    require((not lexical or owner[-len(lexical):]==lexical) if extensions else owner==lexical,'nominal full tree/source path mismatch')
                    require((entity.get('effective_access','').rsplit('.',1)[-1] in PUBLIC)==((scope['explicitAccess'] or 'internal') in PUBLIC),'nominal source/compiler access disagreement')
                    origin_attributes=[]
                    if any(a['text'].startswith('@_originallyDefinedIn') for a in own_attributes(scope)):
                        origin_attributes=[a for a in own_attributes(scope) if a['text'].startswith('@_originallyDefinedIn')]
                        parsed_origins=[]
                        for attribute in origin_attributes:
                            matched=re.fullmatch(r'@_originallyDefinedIn\(module: "(\w+)", (iOS|macOS|tvOS|watchOS|visionOS) ([0-9]+(?:\.[0-9]+)*)\)',attribute['text'])
                            require(matched is not None,'malformed declaration-bound original-module annotation')
                            parsed_origins.append(matched.groups())
                        require(len(parsed_origins)==len(set((x[0],x[1]) for x in parsed_origins)),'duplicate own original-module platform annotations')
                        require(len({x[0] for x in parsed_origins if x[1]=='macOS'})<=1,'ambiguous own macOS original-module annotation')
                    namespaces=sorted({namespace}|({x[0] for x in parsed_origins if x[1]=='macOS'} if origin_attributes else set()))
                    nominals.append({'namespaces':namespaces,'treeNode':nominal_node,'treeExtensionContext':tree_extension,'originAttributes':origin_attributes,'scope':scope,'entity':entity,'namespace':namespace,'path':owner+[scope['name']],'sourceModule':module})
                except ValueError as error:held_nominals[(module,scope['line'])]=str(error)
        external_nominals=self.external_nominals(raw,trees)
        @lru_cache(maxsize=None)
        def resolve_scope(module,line):
            scope=scopes[module][line]
            if scope['kind'] in NOMINAL:
                matches=[n for n in nominals if n['sourceModule']==module and n['scope']['line']==line]
            else:
                parts=scope['name'].split('.');matches=[]
                for nominal in nominals:
                    if all(q in set(nominal['namespaces'])|{nominal['sourceModule']}|({nominal['treeExtensionContext']['nominalNamespace']} if nominal['treeExtensionContext'] else set()) for q in scope.get('targetNamespaceQualifiers',[])) and (parts==[nominal['sourceModule']]+nominal['path'] or any(parts==[ns]+nominal['path'] for ns in nominal['namespaces']) or (parts==nominal['path'] and nominal['sourceModule']==module) or (nominal['treeExtensionContext'] is not None and parts==[nominal['treeExtensionContext']['nominalNamespace']]+nominal['path'])):matches.append(nominal)
                external_matches=[n for n in external_nominals if parts==[n['sourceModule']]+n.get('sourceTargetPath',n['path'])]
                if not matches and len(external_matches)==1:
                    require(scope['explicitAccess'] in PUBLIC|{None},'extension access cap nonpublic')
                    return external_matches[0]
            require(len(matches)==1,'owner nominal resolution ambiguous/absent')
            resolved=matches[0]
            chain=[];parent=None
            for ancestor_line in resolved['scope']['scopeLines']:
                parent=resolve_scope(resolved['sourceModule'],ancestor_line)
                chain=parent['chain']
            if parent is not None:
                require(resolved['path']==parent['path']+[resolved['scope']['name']],'nested nominal exact full parent path disagreement')
                parents=[n for n in resolved['treeNode']['children'] if n['kind'] in NOMINAL_TREE_OWNERS or n['kind'] in {'Module','Extension'}]
                require(len(parents)==1 and parent['nominalTree']['kind'] in NOMINAL_TREE_OWNERS,'nested nominal full parent tree cardinality')
                actual_parent=parents[0];expected_parent=parent['nominalTree']
                if actual_parent['kind']=='Extension':
                    extension_modules=[n for n in actual_parent['children'] if n['kind']=='Module'];extension_nominals=[n for n in actual_parent['children'] if n['kind'] in NOMINAL_TREE_OWNERS]
                    require(len(extension_modules)==len(extension_nominals)==1 and extension_modules[0]['text']==self.source_namespace(resolved['sourceModule'],raw[resolved['sourceModule']+':source']),'nested nominal exact direct extension module')
                    actual_parent=extension_nominals[0]
                require(actual_parent==expected_parent,'nested nominal full resolved parent tree identity disagreement')
            own=resolved['scope'];require(own['explicitAccess'] in PUBLIC,'enclosing nominal ancestor nonpublic/unspecified')
            chain=chain+[{'module':own['module'],'line':own['line'],'name':own['name'],'kind':own['kind'],'access':own['explicitAccess'],'text':own['text'],'attributes':own_attributes(own)}]
            if scope['kind']=='extension':require(scope['explicitAccess'] in PUBLIC|{None},'extension access cap nonpublic')
            return {'sourceModule':resolved['sourceModule'],'namespace':resolved['namespace'],'namespaces':resolved['namespaces'],'originAttributes':resolved['originAttributes'],'path':resolved['path'],'nominalUsr':resolved['entity']['usr'],'nominalTree':resolved['treeNode'],'chain':chain}
        results=[];source_starts=[];keys=set();v12_keys={(r['module'],r['line'],r['name'].strip('`')) for r in self.v12['declarations']};source_keys=set()
        for module,source_model in parsed.items():
            for declaration in source_model['declarations']:
                if declaration['kind']=='extension':continue
                key=[module,'arm64e-apple-macos.swiftinterface',declaration['line'],declaration['name']]
                require(tuple(key) not in keys,'source declaration key duplicate');keys.add(tuple(key));source_keys.add((module,declaration['line'],declaration['name']))
                row={'key':key,'kind':declaration['kind'],'signature':declaration['text'],'explicitAccess':declaration['explicitAccess'],'scopeLines':declaration['scopeLines'],'conditions':declaration['conditions'],'lineageV12':(module,declaration['line'],declaration['name']) in v12_keys,'attributes':own_attributes(declaration)}
                source_starts.append(key)
                if declaration['kind']=='deinit' and active(declaration,selected_by_module[module]):
                    row['compilerAccessAST']=next(n for n in destructor_nodes[module] if n['line']==declaration['line'])
                if declaration['insideFunction']:row.update(status='excluded-local-declaration',reason='actual lexical function/property body')
                elif not active(declaration,selected_by_module[module]):row.update(status='excluded-inactive-source-branch',reason='actual compiler-selected exact branch')
                elif declaration['kind']=='deinit' and self.destructor_access(raw,module,declaration,destructor_nodes[module]) not in PUBLIC:
                    row.update(status='excluded-nonpublic-compiler-access',reason='successful exact-target whole-interface AST reports destructor member access '+self.destructor_access(raw,module,declaration,destructor_nodes[module]),compilerAccessEvidence='exact physical source AST; canonical identity remains separately reconstructed')
                elif declaration['explicitAccess'] is not None and declaration['explicitAccess'] not in PUBLIC:
                    row.update(status='excluded-nonpublic-source',reason='explicit actual source declaration access '+declaration['explicitAccess'])
                elif declaration['kind']!='deinit' and declaration['explicitAccess'] is None and not (declaration['scopeLines'] and ((scopes[module][declaration['scopeLines'][-1]]['kind']=='protocol' and declaration['kind'] in {'func','var','subscript','init','associatedtype','typealias'}) or (scopes[module][declaration['scopeLines'][-1]]['kind']=='enum' and declaration['kind']=='case') or (scopes[module][declaration['scopeLines'][-1]]['kind']=='extension' and scopes[module][declaration['scopeLines'][-1]]['explicitAccess'] in PUBLIC))):
                    row.update(status='excluded-nonpublic-source',reason='actual source family default internal access outside protocol/enum/public-extension rules')
                else:
                    try:
                        owner=None
                        for line in declaration['scopeLines']:owner=resolve_scope(module,line)
                        row['owner']=owner
                        access=self.destructor_access(raw,module,declaration,destructor_nodes[module]) if declaration['kind']=='deinit' else declaration['explicitAccess'];parent=scopes[module][declaration['scopeLines'][-1]] if declaration['scopeLines'] else None
                        if access is None:
                            inherited=(parent and parent['kind']=='protocol' and declaration['kind'] in {'func','var','subscript','init','associatedtype','typealias'}) or (parent and parent['kind']=='enum' and declaration['kind']=='case') or (parent and parent['kind']=='extension' and parent['explicitAccess'] in PUBLIC)
                            require(inherited,'member default access is not proven public')
                            access='public';row['accessRule']='protocol/enum/public-extension inherited access'
                        else:row['accessRule']='successful exact-target AST destructor member access' if declaration['kind']=='deinit' else 'explicit source access'
                        require(access in PUBLIC,'declaration source access nonpublic')
                        declared_nominal=resolve_scope(module,declaration['line']) if declaration['kind'] in NOMINAL else None
                        row['effectivePublic']=True
                        records=[e for e in by_line[module][declaration['line']] if e['column']==declaration_column(raw[module+':source'],declaration)]
                        projected=(module,declaration['line'],declaration['name']) in PROJECTED_DUPLICATES
                        require(len(records)==(2 if projected else 1),'member raw identity/cardinality absent/ambiguous')
                        if projected:
                            require(records[0]==records[1] and digest(raw['projectedDuplicateProof'])==DUPLICATE_PROOF_HASH,'exact bounded projected duplicate/raw proof binding')
                            row['rawCardinality']=2;row['identityEvidence']='exact frozen projected index duplicate proof; cursor backing-property USRs are distinct'
                        entity=records[0];require(norm(entity['name'])==declaration['name'],'source token/exact raw declaration name disagreement')
                        require(not entity.get('is_implicit'),'source declaration resolved to implicit raw record')
                        require(strict.entity_kind_matches({'kind':declaration['kind']},entity) if declaration['kind'] not in {'init','deinit','subscript','associatedtype','actor'} else entity['kind']==RAW_SPECIAL[declaration['kind']],'raw declaration family mismatch')
                        require((self.destructor_access(raw,module,declaration,destructor_nodes[module]) in PUBLIC) if declaration['kind']=='deinit' else (entity.get('effective_access','').rsplit('.',1)[-1] in PUBLIC),'raw/compiler effective public access disagreement')
                        physical=[scopes[module][n] for n in declaration['scopeLines']]
                        context=entity['sourcekitContext']
                        # SourceKit omits certain extension container dictionaries. An
                        # exact direct compiler Extension tree can independently restore
                        # this one physical source owner, never a guessed context map.
                        omitted_extension=not context and len(physical)==1 and physical[0]['kind']=='extension'
                        require(len(context)==len(physical) or omitted_extension,'raw lexical owner cardinality disagreement')
                        require(all(c['line']==s['line'] and norm(c['name']) in {s['name'],s['name'].split('.')[-1]} for c,s in zip(context,physical)),'raw lexical owner full source identity disagreement')
                        require(entity['usr'] in trees,'member actual demangle tree absent')
                        namespace,path,direct=declaration_tree(trees[entity['usr']],declaration['kind'],declaration['name'])
                        member_extensions=[n for n in direct['children'] if n['kind']=='Extension']
                        if omitted_extension:require(len(member_extensions)==1,'omitted raw extension lacks exact direct compiler Extension tree')
                        for extension in member_extensions:require(extension_context(extension)['extensionModule']==self.source_namespace(module,raw[module+':source']),'member direct extension module disagrees with actual source module')
                        direct_owners=[n for n in direct['children'] if n['kind'] in NOMINAL_TREE_OWNERS or n['kind'] in {'Module','Extension'}]
                        require(len(direct_owners)==1,'member exact full owner cardinality')
                        exact_owner=direct_owners[0]
                        if exact_owner['kind']=='Extension':
                            targets=[n for n in exact_owner['children'] if n['kind'] in NOMINAL_TREE_OWNERS];require(len(targets)==1,'member exact full extension target cardinality');exact_owner=targets[0]
                        if owner:require(exact_owner==owner['nominalTree'],'member entire resolved nominal owner tree disagreement')
                        else:require(exact_owner['kind']=='Module' and exact_owner['text']==self.source_namespace(module,raw[module+':source']),'member exact free declaration source namespace')
                        require(path==(owner['path'] if owner else []) and (namespace==declared_nominal['namespace'] if declared_nominal else (owner is None or namespace in owner['namespaces'])),'member exact tree owner namespace/path disagreement')
                        row.update(status='eligible-compiler-mapped',reason='actual source public ancestor/default rule plus exact raw identity/tree',usr=entity['usr'],rawEntity=entity,compilerNamespace=namespace,compilerOwnerPath=path,compilerDeclarationName=entity['name'],compilerPath='.'.join([namespace,*path,entity['name']]))
                        attribute_contexts=[{'role':'declaration','module':module,'line':declaration['line'],'attributes':own_attributes(declaration)}]
                        attribute_contexts.extend({'role':'physical-extension','module':module,'line':s['line'],'attributes':own_attributes(s)} for s in physical if s['kind']=='extension')
                        attribute_contexts.extend({'role':'resolved-nominal-ancestor','module':a['module'],'line':a['line'],'attributes':a['attributes']} for a in (owner['chain'] if owner else []))
                        restrictions=[]
                        for context_attributes in attribute_contexts:
                            for attribute in context_attributes['attributes']:
                                text=attribute['text']
                                category=None
                                if re.fullmatch(r'@_documentation\(visibility: (?:private|internal)\)',text):category='documentation-hidden'
                                elif re.fullmatch(r'@_?available\((?:macOS|\*), unavailable(?:,.*)?\)',text):category='macOS-unavailable'
                                elif text.startswith('@_spi('):category='spi'
                                if category:restrictions.append({'category':category,'role':context_attributes['role'],'module':context_attributes['module'],'ownerLine':context_attributes['line'],'attribute':attribute})
                        row['attributedRestrictions']=restrictions
                        if any(x['category']=='macOS-unavailable' for x in restrictions):row.update(status='public-compiler-mapped-attributed-unavailable',reason='exact active source macOS-unavailable declaration/ancestor attribute')
                        elif any(x['category']=='documentation-hidden' for x in restrictions):row.update(status='public-compiler-mapped-documentation-hidden',reason='exact source documentation visibility attribute; compiler public identity retained')
                    except ValueError as error:
                        reason=str(error)
                        proved_nonpublic=reason in {'enclosing nominal ancestor nonpublic/unspecified','extension access cap nonpublic','declaration source access nonpublic','member default access is not proven public'}
                        row.update(status='excluded-nonpublic-source' if proved_nonpublic else 'held-unresolved',reason=reason)
                results.append(row)
        repairs=[]
        for inherited in self.v12['declarations']:
            key=(inherited['module'],inherited['line'],inherited['name'].strip('`'))
            if key in source_keys:continue
            candidates=[d for d in parsed[inherited['module']]['declarations'] if d['line']==inherited['line'] and d['kind']==inherited['kind'] and d['text'][:1000]==inherited['signature']]
            if len(candidates)==1:
                actual=candidates[0];repairs.append({'v12Key':[inherited['module'],inherited['interface'],inherited['line'],inherited['name']],'actualSourceName':actual['name'],'kind':actual['kind'],'reason':'exact source family/signature proves v12 name-extraction defect'})
                source_keys.add(key)
                for result in results:
                    if result['key'][0]==inherited['module'] and result['key'][2]==inherited['line'] and result['key'][3]==actual['name']:result['lineageV12']=True;result['v12RepairedName']=inherited['name']
        missing=sorted(v12_keys-source_keys)
        for key in missing:results.append({'key':[key[0],'arm64e-apple-macos.swiftinterface',key[1],key[2]],'status':'held-v12-start-not-reconstructed','reason':'source family/start extractor has not independently reconstructed this v12 start','lineageV12':True})
        compiler_inventory=[];public_children=[]
        accessor_nodes={module:compiler_children.ast_nodes(raw[module+':destructorAST']) for module in entities}
        source_rows={tuple(r['key']):r for r in results}
        row_keys={(r['key'][0],r['key'][2],r['key'][3]) for r in results}
        for module,records in entities.items():
            for index,entity in enumerate(records):
                key=(module,entity['line'],norm(entity['name']))
                category='source-start-present' if key in row_keys else 'held-compiler-record-without-source-start'
                parent_anchor=None;child_evidence=None;container_evidence=None
                if entity['kind'].startswith('source.lang.swift.decl.extension.'):
                    require(entity['line'] in scopes[module] and scopes[module][entity['line']]['kind']=='extension','raw compiler extension lacks actual lexical source header')
                    scope=scopes[module][entity['line']]
                    source_line=raw[module+':source'].splitlines()[entity['line']-1]
                    column=entity['column']-1
                    require(isinstance(column,int) and column>=0 and re.match(re.escape(entity['name'])+r'(?![\w$])',source_line[column:]),'compiler extension exact source token/column')
                    require(scope['name'].split('.')[-1]==entity['name'] and re.search(r'\bextension\s+(?:[A-Za-z_$][\w$]*(?:\.|::))*$',structural_lines(raw[module+':source'])[entity['line']-1][:column]),'compiler extension full lexical target/source column')
                    positions=[e for e in records if e['line']==entity['line'] and e['column']==entity['column']]
                    require(len(positions)==1,'compiler extension raw physical cardinality')
                    captured=[e for e in helper.entities(self.inputs[module+':index']) if e['line']==entity['line'] and e['column']==entity['column']]
                    require(len(captured)==1 and captured[0]==entity,'compiler extension exact captured kind/USR/owner identity')
                    require(not entity.get('is_implicit') and entity['kind'].rsplit('.',1)[-1] in {'struct','class','enum','protocol'} and entity['usr'].startswith('s:e:'),'compiler extension observed explicit typed container')
                    container_evidence={'status':'attributed-source-extension-container','sourceLine':entity['line'],'sourceColumn':entity['column'],'sourceTarget':scope['name'],'sourceHeader':source_line,'conditions':scope['conditions'],'rawKind':entity['kind'],'rawUsr':entity['usr'],'rawContext':entity['sourcekitContext'],'standalonePublicAPI':False}
                    category='source-extension-container'
                elif entity['kind'] in {'source.lang.swift.decl.generic_type_param','source.lang.swift.decl.function.accessor.getter','source.lang.swift.decl.function.accessor.setter'} or entity['name'].startswith('init:'):
                    require(entity['sourcekitContext'],'compiler child has no exact raw parent')
                    context_parent=entity['sourcekitContext'][-1]
                    parents=[e for e in by_line[module][context_parent['line']] if e['usr']==context_parent['usr'] and e['name']==context_parent['name'] and e['kind']==context_parent['kind']]
                    require(parents and all(e==parents[0] for e in parents),'compiler child raw parent exact identity/cardinality')
                    parent_key=(module,context_parent['line'],norm(context_parent['name']))
                    require(parent_key in row_keys,'compiler child parent absent from actual source universe')
                    parent_anchor={'sourceKey':[module,'arm64e-apple-macos.swiftinterface',context_parent['line'],norm(context_parent['name'])],'usr':context_parent['usr'],'kind':context_parent['kind'],'rawCardinality':len(parents)}
                    category='source-generic-parameter' if entity['kind']=='source.lang.swift.decl.generic_type_param' else ('source-property-initializer' if entity['name'].startswith('init:') else 'source-property-accessor')
                    if category in {'source-generic-parameter','source-property-initializer'}:
                        require(len(parents)==1,'compiler parameter/initializer exact raw parent cardinality')
                        positions=[e for e in records if e['line']==entity['line'] and e['column']==entity['column']]
                        require(len(positions)==1,'compiler parameter/initializer raw physical cardinality')
                        try:
                            tree=(compiler_children.parameter if category=='source-generic-parameter' else compiler_children.initializer)(entity,parents[0],trees,raw[module+':source'])
                            child_evidence={'status':'attributed-typed-parent-component','tree':tree,'parentUsr':parents[0]['usr'],'parentSourceKey':parent_anchor['sourceKey'],'reason':'exact compiler child family/source token/full parent tree'}
                        except ValueError as error:
                            if category=='source-generic-parameter' and (module,entity['line']) in PHYSICAL_GENERIC_COMPONENTS and str(error)=='generic parameter exact full parent tree':
                                require(len(parents)==1,'physical generic exact raw parent cardinality')
                                baseline=[e for e in helper.entities(self.inputs[module+':index']) if e['line']==entity['line'] and e['column']==entity['column']]
                                require(len(baseline)==1 and entity==baseline[0],'physical generic actual captured raw identity changed')
                                actual_trees=helper.trees(self.actual_trees)
                                require(trees[entity['usr']]==actual_trees[entity['usr']] and trees[parents[0]['usr']]==actual_trees[parents[0]['usr']],'physical generic captured actual tree witness mismatch')
                                extension_context_raw=entity['sourcekitContext'][-2]
                                extensions=[e for e in records if all(e.get(k)==extension_context_raw.get(k) for k in ('kind','name','usr','line','column'))]
                                require(len(extensions)==1,'physical generic exact raw extension cardinality')
                                typed=compiler_children.physical_parameter(entity,parents[0],extensions[0],raw[module+':source'],raw[module+':destructorAST'],self.paths[module+':source'])
                                child_evidence={'status':'attributed-physical-parent-component-tree-disagreement','reason':'actual generic token/nested raw parent & successful typed AST physical owner; tree IDs remain distinct','parentUsr':parents[0]['usr'],'parentSourceKey':parent_anchor['sourceKey'],'childTree':trees[entity['usr']],'parentTree':trees[parents[0]['usr']],'typedPhysicalParent':typed,'canonicalIdentityTransferred':False}
                            else:child_evidence={'status':'held-unresolved-typed-parent','reason':str(error),'parentUsr':parents[0]['usr'],'parentSourceKey':parent_anchor['sourceKey']}
                    if category=='source-property-accessor':
                        parent=parents[0]
                        positions=[e for e in records if e['line']==entity['line'] and e['column']==entity['column']]
                        projected_child=(module,parent['line'],norm(parent['name'])) in PROJECTED_DUPLICATES
                        require(len(parents)==(2 if projected_child else 1),'compiler accessor exact raw parent cardinality')
                        require(len(positions)==(2 if projected_child else 1),'compiler accessor raw physical cardinality')
                        if projected_child:require(entity['kind']=='source.lang.swift.decl.function.accessor.getter' and positions[0]==positions[1] and digest(raw['projectedDuplicateProof'])==DUPLICATE_PROOF_HASH,'exact frozen projected getter pair/source/raw proof binding')
                        typed=compiler_children.accessor(entity,parent,accessor_nodes[module],trees,self.paths[module+':source'],raw[module+':source'])
                        raw_access=entity.get('effective_access')
                        require(raw_access is None or ((raw_access.rsplit('.',1)[-1] in PUBLIC)==(typed['access'] in PUBLIC)),'compiler accessor raw/AST access disagreement')
                        parent_row=source_rows[tuple(parent_anchor['sourceKey'])]
                        component_context=parsed[module]['lines'][entity['line']]
                        require(active(component_context,selected_by_module[module]),'compiler accessor source branch is not active')
                        component_text=raw[module+':source'].splitlines()[entity['line']-1]
                        require(re.match(r'(get|set)\b',component_text[entity['column']-1:]) and component_text[entity['column']-1:].startswith('get' if entity['kind'].endswith('.getter') else 'set'),'compiler accessor actual source family/token')
                        component_attrs=[];cursor=entity['line']-1
                        while cursor>parent['line']:
                            text=raw[module+':source'].splitlines()[cursor-1].strip()
                            if not text.startswith('@'):break
                            context_line=parsed[module]['lines'][cursor]
                            require(context_line['conditions']==component_context['conditions'] and context_line['scopeLines']==component_context['scopeLines'],'compiler accessor annotation lexical/branch binding')
                            component_attrs.insert(0,{'line':cursor,'text':text});cursor-=1
                        component_attributes=own_attributes({'attributes':component_attrs,'line':entity['line'],'text':component_text.strip()})
                        component_restrictions=[]
                        for attribute in component_attributes:
                            text=attribute['text'];restriction_category=None
                            if re.fullmatch(r'@_documentation\(visibility: (?:private|internal)\)',text):restriction_category='documentation-hidden'
                            elif re.fullmatch(r'@_?available\((?:macOS|\*), unavailable(?:,.*)?\)',text):restriction_category='macOS-unavailable'
                            elif text.startswith('@_spi('):restriction_category='spi'
                            if restriction_category:component_restrictions.append({'category':restriction_category,'role':'accessor-declaration','module':module,'ownerLine':entity['line'],'attribute':attribute})
                        child_evidence={'usr':entity['usr'],'parentUsr':parent['usr'],'parentSourceKey':parent_anchor['sourceKey'],'kind':entity['kind'],'typedAccess':typed['access'],'typedAST':typed,'conditions':component_context['conditions'],'ownSourceAttributes':component_attributes,'parentSourceStatus':parent_row['status'],'parentRawCardinality':len(parents),'projectedDuplicateProof':DUPLICATE_PROOF_HASH if projected_child else None,'graphPresent':entity['usr'] in graph_usrs,'tree':trees[entity['usr']]}
                        if typed['access'] not in PUBLIC:child_evidence.update(status='excluded-nonpublic-compiler-access',reason='successful whole-interface typed accessor AST access')
                        elif parent_row.get('usr'):
                            require(parent_row['usr']==parent['usr'],'qualified accessor parent API USR disagreement')
                            child_evidence.update(status=parent_row['status'],reason='exact typed public property/subscript component',parentCompilerPath=parent_row['compilerPath'],attributedRestrictions=parent_row.get('attributedRestrictions',[])+component_restrictions)
                            if any(r['category']=='macOS-unavailable' for r in child_evidence['attributedRestrictions']):child_evidence['status']='public-compiler-mapped-attributed-unavailable'
                            elif any(r['category']=='documentation-hidden' for r in child_evidence['attributedRestrictions']):child_evidence['status']='public-compiler-mapped-documentation-hidden'
                        elif parent_row['status']=='excluded-nonpublic-source' and parent_row['reason']=='enclosing nominal ancestor nonpublic/unspecified':
                            witnesses=[]
                            for source_scope in [scopes[module][line] for line in parent_row['scopeLines']]:
                                if source_scope['kind'] not in NOMINAL or source_scope['explicitAccess'] in PUBLIC:continue
                                require(source_scope['explicitAccess'] in {'internal','package','fileprivate','private'},'accessor nonpublic owner requires explicit source access')
                                own_entities=[e for e in records if e['line']==source_scope['line'] and e['column']==declaration_column(raw[module+':source'],source_scope)]
                                require(len(own_entities)==1,'accessor nonpublic nominal raw cardinality')
                                own_entity=own_entities[0]
                                require(own_entity['name']==source_scope['name'] and own_entity['kind']=='source.lang.swift.decl.'+source_scope['kind'] and own_entity.get('effective_access','').rsplit('.',1)[-1]==source_scope['explicitAccess'],'accessor nonpublic nominal source/raw identity/access')
                                own_ast=[n for n in typed['owners'] if n['line']==source_scope['line'] and n['kind']==source_scope['kind']+'_decl']
                                require(len(own_ast)==1 and own_ast[0]['name']==source_scope['name'] and own_ast[0]['access']==source_scope['explicitAccess'],'accessor nonpublic nominal exact typed AST access')
                                require(own_entity['usr'] in trees,'accessor nonpublic nominal actual tree absent')
                                ns,path,node=declaration_tree(trees[own_entity['usr']],source_scope['kind'],source_scope['name'])
                                parent_tree=trees[parent['usr']]['children'][0]
                                owner_nodes=[n for n in parent_tree['children'] if n['kind'] in NOMINAL_TREE_OWNERS or n['kind']=='Extension']
                                require(len(owner_nodes)==1,'accessor nonpublic parent owner tree cardinality')
                                chain_nodes=[];owner_node=owner_nodes[0]
                                while owner_node['kind'] in NOMINAL_TREE_OWNERS or owner_node['kind']=='Extension':
                                    chain_nodes.append(owner_node)
                                    next_nodes=[n for n in owner_node['children'] if n['kind'] in NOMINAL_TREE_OWNERS or n['kind']=='Extension']
                                    if not next_nodes:break
                                    require(len(next_nodes)==1,'accessor nonpublic parent full nominal ancestry cardinality');owner_node=next_nodes[0]
                                require(node in chain_nodes,'accessor nonpublic exact full nominal parent tree identity')
                                witnesses.append({'sourceScope':source_scope,'rawNominal':own_entity,'typedNominalAST':own_ast[0],'nominalTree':node})
                            require(witnesses,'accessor nonpublic enclosing nominal witness absent')
                            child_evidence.update(status='excluded-nonpublic-parent-api',reason='public typed component is capped by exact source/raw/typed nonpublic enclosing nominal',effectivePublic=False,nonpublicOwnerEvidence=witnesses)
                        else:child_evidence.update(status='held-unresolved-parent-api',reason='public typed accessor requires qualified exact parent API')
                        if typed['access'] in PUBLIC and child_evidence['status']!='excluded-nonpublic-parent-api':public_children.append(child_evidence)

                compiler_inventory.append({'module':module,'rawEntityIndex':index,'line':entity['line'],'name':entity['name'],'usr':entity['usr'],'kind':entity['kind'],'effectiveAccess':entity.get('effective_access'),'isImplicit':bool(entity.get('is_implicit')),'category':category,'parentAnchor':parent_anchor,'rawContext':entity['sourcekitContext'],'childEvidence':child_evidence,'containerEvidence':container_evidence})
        supplement=defaultdict(list)
        for row in results:
            if row.get('usr'):supplement[row['usr']].append({'sourceKey':row['key'],'compilerPath':row['compilerPath'],'status':row['status'],'kind':row['kind'],'ancestor':row.get('owner'),'accessRule':row.get('accessRule'),'restrictions':row.get('attributedRestrictions',[])})
        public_catalogue=[]
        for usr,source_rows in sorted(supplement.items()):
            paths={row['compilerPath'] for row in source_rows};require(len(paths)==1,'same exact compiler USR has ambiguous canonical owner path')
            statuses={row['status'] for row in source_rows};require(len(statuses)==1,'same exact compiler USR has conflicting source eligibility')
            source_status=next(iter(statuses));status='inventory' if source_status=='eligible-compiler-mapped' else 'hidden'
            entry={'usr':usr,'path':next(iter(paths)),'status':status,'graphPresent':usr in graph_usrs,'compilerEvidencePresent':True,'sourceDeclarations':source_rows}
            if status=='hidden':
                category='macOS-unavailable' if source_status=='public-compiler-mapped-attributed-unavailable' else 'documentation-hidden'
                witnesses=sorted({r['module']+':'+str(r['attribute']['line'])+' '+r['attribute']['text'] for row in source_rows for r in row['restrictions'] if r['category']==category})
                require(witnesses,'hidden compiler public identity lacks exact source attribution')
                entry['hiddenReason']=category+': '+'; '.join(witnesses)
            public_catalogue.append(entry)
        child_groups={}
        for child in public_children:
            usr=child['usr']
            if usr in child_groups:
                require(child_groups[usr]['evidence']==child,'same accessor USR has conflicting source/parent/access evidence')
                child_groups[usr]['rawCardinality']+=1
            else:child_groups[usr]={'evidence':child,'rawCardinality':1}
        public_child_records=len(public_children)
        public_children=[{**value['evidence'],'rawCardinality':value['rawCardinality'],'rawOccurrences':[{'module':e['module'],'rawEntityIndex':e['rawEntityIndex'],'parentAnchor':e['parentAnchor']} for e in compiler_inventory if e['usr']==usr and e['category']=='source-property-accessor']} for usr,value in sorted(child_groups.items())]
        counts=Counter(r['status'] for r in results);reasons=Counter(r['reason'] for r in results if r['status'].startswith('held'))
        held_records=sum(e['category'].startswith('held') for e in compiler_inventory)
        held_components=sum(bool(e['childEvidence']) and e['childEvidence']['status'].startswith('held') for e in compiler_inventory)
        held_public_children=sum(c['status'].startswith('held') for c in public_children)
        complete=not missing and not reasons and not held_records and not held_components and not held_public_children
        return copy.deepcopy({'kind':'public-ancestor-source-census-proof','version':1,'status':'complete-source-public-api-accounting' if complete else 'incomplete-held-source-universe-reconciliation','scope':'all actual declaration starts in two pinned SDK interfaces, all 19185 observed SourceKit declaration records & preserved 108272 graph USRs; compiler-only synthesized components absent these inputs are outside scope','v12DeclarationStarts':len(self.v12['declarations']),'fullSourceDeclarationStarts':len(source_starts),'addedSourceDeclarationStarts':sum(not r.get('lineageV12') for r in results),'sourceNominalScopeCount':sum(s['kind'] in NOMINAL for m in parsed.values() for s in m['scopes']),'sourceExtensionScopeCount':sum(s['kind']=='extension' for m in parsed.values() for s in m['scopes']),'byStatus':dict(sorted(counts.items())),'heldReasons':dict(sorted(reasons.items())),'unreconstructedV12Starts':len(missing),'v12SourceNameRepairs':repairs,'compilerRecordCount':len(compiler_inventory),'heldCompilerRecordCount':held_records,'compilerRecordCategories':dict(Counter(e['category'] for e in compiler_inventory)),'heldCompilerComponentCount':held_components,'compilerInventory':compiler_inventory,'publicCompilerChildren':public_children,'observedAccessorRecordCount':sum(e['category']=='source-property-accessor' for e in compiler_inventory),'typedPublicAccessorRecordCount':sum(e['category']=='source-property-accessor' and e['childEvidence']['typedAccess'] in PUBLIC for e in compiler_inventory),'nonpublicParentAccessorRecordCount':sum(e['category']=='source-property-accessor' and e['childEvidence']['status']=='excluded-nonpublic-parent-api' for e in compiler_inventory),'publicCompilerChildRecordCount':public_child_records,'publicCompilerChildUsrCount':len(public_children),'heldPublicCompilerChildCount':held_public_children,'publicCompilerCatalogue':public_catalogue,'publicCompilerCatalogueUsrCount':len(public_catalogue),'graphAbsentPublicCompilerUsrCount':sum(not s['graphPresent'] for s in public_catalogue),'heldNominalReasons':dict(Counter(held_nominals.values())),'heldNominals':[{'module':m,'line':n,'scope':scopes[m][n],'reason':why} for (m,n),why in held_nominals.items()],'rows':results,'compilerSelectedBranches':selected})


def load_artifact(path,expected_sha256,*,prefer_archive=False):
    """Replay a caller-pinned independently cleared artifact using actual input bytes."""
    path=Path(path);require(digest(path.read_bytes())==expected_sha256,'cleared proof artifact byte pin mismatch')
    serialized=path.read_bytes();decoded=gzip.decompress(serialized) if path.suffix=='.gz' else serialized
    evidence=json.loads(decoded)
    require(evidence['dependencies'].get('pinnedDependencies')==frozen_dependency_descriptors(),'pinned production archive/helper dependency closure')
    source_dependencies=evidence['dependencies'].get('productionSources')
    require(isinstance(source_dependencies,dict) and set(source_dependencies)=={'guard','compilerChildren','externalScopes','generator'},'production helper dependency closure')
    expected_sources={'guard':HERE/'exact_public_ancestor.py','compilerChildren':HERE/'compiler_children.py','externalScopes':HERE/'external_scopes.py','generator':HERE/'generate_public_ancestor.py'}
    for key,source in expected_sources.items():
        descriptor=source_dependencies[key]
        require(descriptor['path']==str(source) and digest(source.read_bytes())==descriptor['sha256'],'production helper source pin changed: '+key)
    require(evidence['dependencies']['lexicalParser']=={'path':str(HERE/'lexical_model_v2.py'),'sha256':LEXICAL_HASH} and evidence['dependencies']['rawParserSha256']==HELPER_HASH and evidence['dependencies']['strictRequestParserSha256']==STRICT_HASH,'frozen parser dependency closure')
    require(type(prefer_archive) is bool,'archive preference must be strict boolean')
    reader=archive_byte_reader()
    verify_destructor_dependency(read_bytes=reader,force_archive=prefer_archive)
    v=Validator.__new__(Validator);v.archive_reader=reader;v.prefer_archive=prefer_archive;inputs={};v.paths={};pins={}
    for key,descriptor in evidence['inputs'].items():
        path=Path(descriptor['path']);actual=path
        if prefer_archive or not actual.is_file():
            relative=Path(descriptor['repositoryPath']);require(not relative.is_absolute() and '..' not in relative.parts,'snapshot repository fallback path')
            actual=ROOT/relative
        data=actual.read_bytes();require(digest(data)==descriptor['sha256'],'snapshot hash mismatch '+key)
        inputs[key]=data.decode();pins[key]=descriptor['sha256'];v.paths[key]=str(path)
    require(pins['immutable836']==LINK_HASH and pins['v12']==V12_HASH,'immutable snapshot authority mismatch')
    v.inputs=MappingProxyType(inputs);v.pins=MappingProxyType(pins);v.link=json.loads(inputs['immutable836']);v.v12=json.loads(inputs['v12'])
    v.tool_pins={}
    for name in ('compiler','sourcekitd','sourcekitLsp'):
        d=v.link['toolchainEvidence'][name];v.tool_pins[name]={'path':d.get('executablePath',d.get('path')),'sha256':d['sha256']}
    v.tool_pins['demangler']={'path':str(helper.DEMANGLE),'sha256':DEMANGLE_HASH}
    require(v.tool_pins==evidence['tools'],'tool snapshot authority mismatch')
    v.actual_processes=inputs['processResults'];v.actual_trees=inputs['trees']
    external_usrs={e['usr'] for record in v.external_modules(inputs) for e in helper.entities(inputs['external:'+record['module']+':index']) if e['kind'] in {'source.lang.swift.decl.'+k for k in NOMINAL} and not e.get('is_implicit') and e['usr'].startswith('s:')}
    v.swift16=archived_swift16.ArchivedExactSwift16(read_bytes=reader,force_archive=prefer_archive)
    v.clang=clang.ExactClangOwners(read_bytes=reader,force_archive=prefer_archive)
    external_usrs|={r['canonicalUsr'] for r in v.swift16_correspondences(inputs).values()}
    v.tree_usrs=sorted(external_usrs|{e['usr'] for module in ('SwiftUI','SwiftUICore') for e in helper.entities(inputs[module+':index']) if e['usr'].startswith('s:') and not e['usr'].startswith('s:e:') and not e.get('is_implicit')})
    for interface in v.link['interfaces']:
        module=interface['module']
        for label,path_field,hash_field in [('source','path','sha256'),('index','indexOutput','indexOutputSha256'),('request','indexRequest','indexRequestSha256')]:
            key=module+':'+(('lineage'+label.title()) if module=='SwiftUICore' and label in {'index','request'} else label);actual_path=Path(interface[path_field]);actual_path=actual_path if actual_path.is_absolute() else ROOT/actual_path
            require(pins[key]==interface[hash_field] and Path(v.paths[key])==actual_path,'immutable SDK/source/index/request snapshot descriptor mismatch')
    for label,(name,sha) in CORE_PINS.items():
        require(pins['SwiftUICore:'+label]==sha and Path(v.paths['SwiftUICore:'+label])==CORE_FOLDER/name,'cleared Core canonical capture descriptor changed')
    require(pins['destructorProof']==DESTRUCTOR_PROOF_HASH,'cleared destructor snapshot pin')
    for module in ('SwiftUI','SwiftUICore'):
        require(pins[module+':destructorAST']==digest(destructor_archive.ast_bytes(module,read_bytes=reader,force_archive=prefer_archive)),'cleared destructor actual AST snapshot pin')
    require(actual_graph_closure(v.link,prefer_archive=prefer_archive)==inputs['graphUsrClosure'],'actual archived/original graph closure snapshot mismatch')
    v.accept(evidence['resolution'])
    return v,evidence
