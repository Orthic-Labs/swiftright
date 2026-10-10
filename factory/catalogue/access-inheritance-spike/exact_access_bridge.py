#!/usr/bin/env python3
"""Fail-closed, reusable validator for compiler-reported enum-case access."""
from __future__ import annotations
import hashlib,json,os,re,subprocess
from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[3]
SPIKE=ROOT/'factory/catalogue/compiler-cursor-spike'
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(SPIKE))
from strict_match import request_identity_matches
EXPECTED_LINK_SHA256='836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec'
EXPECTED_SEED_SHA256='1476e12485b394535903e684475deb1af6e3e4bad0181147d39cb6a93100c5ab'
EXPECTED_RECEIPT_SHA256='88d54fc063611e57f060c5047dc1659a9f912053e28b5ccff0c2bc26ae98446f'
SDK=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk')
TARGET='arm64-apple-macosx27.0'
ACCESS={'public','open','package','internal','fileprivate','private','less_than_fileprivate','unknown'}
TYPE_KINDS={'struct','enum','class','actor','protocol'}


def sha(path:Path)->str: return hashlib.sha256(path.read_bytes()).hexdigest()
def norm_name(value:str)->str: return str(value).strip('`').split('(',1)[0]
def normalized_context(context:list[dict])->list[str]:
    return [str(x.get('name','')).split('.')[-1].split('<',1)[0] for x in context]
def access_suffix(value:object)->str:
    if not isinstance(value,str) or not value: return 'unknown'
    return value.rsplit('.',1)[-1]


def parse_index_declarations(path:Path)->list[dict]:
    """Parse raw sourcekitd response without deduplicating repeated records."""
    out=[]; stack=[]
    for line in path.read_text().splitlines():
        opened=re.match(r'^(\s*)\{$',line)
        if opened:
            stack.append({'indent':len(opened.group(1)),'fields':{}}); continue
        closed=re.match(r'^(\s*)\}(?:,)?$',line)
        if closed:
            indent=len(closed.group(1))
            while stack and stack[-1]['indent']>=indent:
                f=stack.pop()['fields']
                if str(f.get('kind','')).startswith('source.lang.swift.decl.') and all(k in f for k in ('name','usr','line')):
                    f['sourcekitContext']=[{'kind':p['fields'].get('kind'),'name':p['fields'].get('name')}
                        for p in stack if str(p['fields'].get('kind','')).startswith('source.lang.swift.decl.extension')
                          or p['fields'].get('kind') in {'source.lang.swift.decl.struct','source.lang.swift.decl.enum',
                            'source.lang.swift.decl.protocol','source.lang.swift.decl.class','source.lang.swift.decl.actor'}]
                    out.append(f)
            continue
        field=re.match(r'^(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?)(?:,)?$',line)
        if field and stack and stack[-1]['indent']+2==len(field.group(1)):
            _,key,value=field.groups()
            if value.startswith('"'): value=json.loads(value)
            elif value.isdigit(): value=int(value)
            stack[-1]['fields'][key]=value
    return out


def _code_braces(line:str,block_comment_depth:int)->tuple[list[str],int]:
    """Return code-only braces, ignoring nested comments and ordinary/raw strings."""
    braces=[]; i=0; n=len(line); in_string=False; triple=False; raw_hashes=0; escape=False
    while i<n:
        if block_comment_depth:
            if line.startswith('/*',i): block_comment_depth+=1; i+=2; continue
            if line.startswith('*/',i): block_comment_depth-=1; i+=2; continue
            i+=1; continue
        if in_string:
            if escape: escape=False; i+=1; continue
            if line[i]=='\\' and raw_hashes==0: escape=True; i+=1; continue
            closing='"""' if triple else '"'
            suffix='#'*raw_hashes
            if line.startswith(closing+suffix,i):
                i+=len(closing)+len(suffix); in_string=False; triple=False; raw_hashes=0; continue
            i+=1; continue
        if line.startswith('//',i): break
        if line.startswith('/*',i): block_comment_depth=1; i+=2; continue
        # Swift raw strings start with any number of hashes before quote.
        if line[i]=='#':
            j=i
            while j<n and line[j]=='#': j+=1
            if j<n and line[j]=='"':
                raw_hashes=j-i
                triple=line.startswith('"""',j)
                in_string=True; i=j+(3 if triple else 1); continue
        if line.startswith('"""',i): in_string=True; triple=True; i+=3; continue
        if line[i]=='"': in_string=True; i+=1; continue
        if line[i] in '{}': braces.append(line[i])
        i+=1
    return braces,block_comment_depth


def parse_lexical_scopes(interface:Path,module:str|None=None)->dict[int,list[dict]]:
    """Map each source line to complete active lexical type scopes and exact ranges."""
    if module is None:
        match=re.search(r'/Frameworks/([^/]+)\.framework/',str(interface))
        module=match.group(1) if match else None
    if not module: raise ValueError(f'module identity required for {interface}')
    scopes=[]; active=[]; depth=0; comment_depth=0
    decl=re.compile(r'^\s*(?:(?:@[\w.]+(?:\([^)]*\))?)\s+)*(?:(public|open|package|internal|fileprivate|private)\s+)?(?:indirect\s+)?(struct|enum|class|actor|protocol)\s+`?([A-Za-z_$][A-Za-z0-9_$]*)')
    extension_decl=re.compile(r'^\s*extension\s+([A-Za-z_$][A-Za-z0-9_$]*(?:(?:::|\.)[A-Za-z_$][A-Za-z0-9_$]*)*)')
    lines=interface.read_text().splitlines()
    by_line={}
    for line_no,line in enumerate(lines,1):
        by_line[line_no]=list(active)
        match=decl.match(line)
        extension_match=extension_decl.match(line) if not match else None
        opens_type=False
        for token in _code_braces(line,comment_depth)[0]:
            if token=='{':
                depth+=1
                if match and not opens_type:
                    access,kind,name=match.groups()
                    qualified='.'.join([s['name'] for s in active if s['kind'] in TYPE_KINDS or s['kind']=='extension']+[name])
                    scope={'kind':kind,'name':name,'explicitAccess':access or None,
                           'declaration':line.strip(),'startLine':line_no,'endLine':None,
                           'bodyDepth':depth,'resolvedAccess':access or None,
                           'qualifiedName':qualified,'module':module}
                    scopes.append(scope); active.append(scope); opens_type=True
                elif extension_match and not opens_type:
                    target=extension_match.group(1).replace('::','.')
                    parts=target.split('.')
                    if parts[0]==module: parts=parts[1:]
                    qualified_target='.'.join(parts)
                    scope={'kind':'extension','name':parts[-1] if parts else target,
                           'target':extension_match.group(1),'qualifiedTarget':qualified_target,
                           'explicitAccess':None,'declaration':line.strip(),'startLine':line_no,
                           'endLine':None,'bodyDepth':depth,'resolvedAccess':None,
                           'resolvedFromDeclarationLine':None,'module':module}
                    scopes.append(scope); active.append(scope); opens_type=True
            else:
                depth-=1
                if depth<0: raise ValueError(f'unbalanced closing brace in {interface}:{line_no}')
                while active and active[-1]['bodyDepth']>depth:
                    active[-1]['endLine']=line_no
                    active.pop()
        _,comment_depth=_code_braces(line,comment_depth)
    if depth!=0 or active: raise ValueError(f'unbalanced type scopes in {interface}: depth={depth}, open={active[-1:]!r}')
    for scope in scopes:
        if scope['kind']!='extension': continue
        # Resolve only a unique exact qualified declaration in this module.
        # A basename match can incorrectly borrow access from a different owner.
        candidates=[item for item in scopes if item['kind'] in TYPE_KINDS
                    and item.get('qualifiedName')==scope['qualifiedTarget']
                    and item['startLine']<scope['startLine']]
        parts=scope['qualifiedTarget'].split('.')
        owner_chain=[]
        if len(candidates)==1:
            for end in range(1,len(parts)+1):
                prefix='.'.join(parts[:end])
                owners=[item for item in scopes if item['kind'] in TYPE_KINDS
                        and item.get('qualifiedName')==prefix and item['startLine']<scope['startLine']]
                if len(owners)!=1: owner_chain=[]; break
                owner_chain.append(owners[0])
        if owner_chain:
            parent=owner_chain[-1]
            scope['resolvedAccess']=parent['explicitAccess']
            scope['resolvedFromDeclarationLine']=parent['startLine']
            scope['resolvedQualifiedName']=parent['qualifiedName']
            scope['resolvedOwnerChain']=[{k:v for k,v in item.items() if k!='bodyDepth'} for item in owner_chain]
    # Extensions are lexically outside their target type, so restore target
    # owner contexts explicitly. This preserves outer access checks for cases
    # declared in extensions of nested public types.
    for line_no, scopes_on_line in by_line.items():
        expanded=[]
        for scope in scopes_on_line:
            if scope.get('kind')!='extension' or not scope.get('resolvedOwnerChain'):
                expanded.append(scope); continue
            chain=scope['resolvedOwnerChain']
            for owner in chain[:-1]:
                virtual=dict(owner); virtual['scopeRole']='resolved-extension-ancestor'
                expanded.append(virtual)
            extension=dict(scope)
            extension['name']=chain[-1]['name']
            extension['scopeRole']='resolved-extension-target'
            expanded.append(extension)
        by_line[line_no]=expanded
    for scopes_on_line in by_line.values():
        for scope in scopes_on_line:
            scope.pop('bodyDepth',None)
    return by_line


def exact_raw_entity(row:dict, raw_entities:list[dict], module:str)->dict:
    wanted_context=[str(x).split('.')[-1].split('<',1)[0] for x in row['context']]
    matching=[e for e in raw_entities
        if e.get('line')==row['line'] and e.get('kind')=='source.lang.swift.decl.enumelement'
        and norm_name(e.get('name',''))==norm_name(row['name'])
        and normalized_context(e.get('sourcekitContext',[]))==wanted_context]
    if len(matching)!=1: raise ValueError(f'raw entity cardinality {len(matching)} for {module}:{row["line"]}:{row["name"]}')
    e=matching[0]
    if not e.get('usr'): raise ValueError('raw compiler USR missing')
    return e


def validate_request_binding(request_text:str, *, interface:str, sdk:str, target:str, module:str)->bool:
    """Reusable exact request identity gate used before consuming raw entities."""
    return request_identity_matches(request_text,interface=interface,sdk=sdk,target=target,module=module)


def validate_case_link(row:dict, raw_entities:list[dict], scopes:list[dict], *,
                       module:str, live_interface_sha256:str, raw_entity_module:str,
                       request_is_exact:bool)->dict:
    """Validate candidate; raises ValueError on any identity, scope, or access fault."""
    if not request_is_exact: raise ValueError('SourceKit request identity/provenance failed')
    if row.get('kind')!='case': raise ValueError('audit row is not enum case')
    if row.get('module')!=module or raw_entity_module!=module: raise ValueError('wrong module identity')
    if row.get('sourceHash')!='sha256:'+live_interface_sha256: raise ValueError('interface source hash mismatch')
    if row.get('line') is None or row.get('name') is None: raise ValueError('row source identity missing')
    e=exact_raw_entity(row,raw_entities,module)
    if e.get('line')!=row['line'] or norm_name(e.get('name',''))!=norm_name(row['name']):
        raise ValueError('raw declaration line or name mismatch')
    if e.get('kind')!='source.lang.swift.decl.enumelement': raise ValueError('raw declaration kind mismatch')
    if normalized_context(e.get('sourcekitContext',[]))!=[str(x).split('.')[-1].split('<',1)[0] for x in row['context']]:
        raise ValueError('raw compiler context mismatch')
    if len(scopes)!=len(row['context']) or [s['name'] for s in scopes]!=[str(x).split('.')[-1].split('<',1)[0] for x in row['context']]:
        raise ValueError('lexical owner/context mismatch')
    if not all(s.get('scopeRole')=='resolved-extension-ancestor' or
               s.get('startLine',0)<=row['line']<=s.get('endLine',-1) for s in scopes):
        raise ValueError('lexical scope range does not contain case line')
    if any(s.get('resolvedAccess') not in ('public','open') for s in scopes):
        raise ValueError('an enclosing lexical type is not explicitly public/open')
    for scope in scopes:
        if scope.get('module')!=module: raise ValueError('lexical scope module identity mismatch')
        if scope.get('kind')=='extension':
            if scope.get('qualifiedTarget')!=scope.get('resolvedQualifiedName'):
                raise ValueError('extension owner does not resolve to exact module-qualified declaration')
            chain=scope.get('resolvedOwnerChain',[])
            if not chain or chain[-1].get('qualifiedName')!=scope.get('qualifiedTarget'):
                raise ValueError('extension original owner chain is incomplete')
            if any(item.get('module')!=module for item in chain):
                raise ValueError('extension original owner chain module mismatch')
            if any(item.get('resolvedAccess') not in ('public','open') for item in chain):
                raise ValueError('extension original owner chain is not public/open')
    if scopes[-1].get('kind')!='enum': raise ValueError('nearest lexical owner is not enum')
    access=access_suffix(e.get('effective_access'))
    if e.get('is_implicit') in (1,'1',True): raise ValueError('raw declaration is implicit')
    if access not in ('public','open'): raise ValueError(f'compiler effective access is {access}')
    return {'auditRowKey':row.get('auditRowKey'),'module':module,'line':row['line'],'name':row['name'],'context':row['context'],
      'usr':e['usr'],'effectiveAccess':access,'sourceHash':row['sourceHash'],
      'rawEntityCount':1,'rawEntityKind':e['kind'],'rawEntityName':e['name'],
      'rawEntityLine':e['line'],'rawEntityColumn':e.get('column'),
      'sourcekitContext':e.get('sourcekitContext',[]),
      'lexicalScopes':[dict(s) for s in scopes]}


def validate_bindings(link:dict)->dict:
    link_path=SPIKE/'link-evidence.json'
    if sha(link_path)!=EXPECTED_LINK_SHA256: raise ValueError('source compiler-link evidence hash changed')
    tool=link['toolchainEvidence']; sdk=Path(tool['sdk'])
    if sdk!=SDK or tool['target']!=TARGET: raise ValueError('SDK/target identity mismatch')
    sdk_settings=sdk/'SDKSettings.json'
    xcode=Path('/Applications/Xcode-27-RC.app/Contents/Developer')
    env={**os.environ,'DEVELOPER_DIR':str(xcode)}
    compiler=tool['compiler']; lsp=tool['sourcekitLsp']; sourcekitd=tool['sourcekitd']
    for label,record,path in [('compiler',compiler,Path(compiler['executablePath'])),
                               ('sourcekitLsp',lsp,Path(lsp['path'])),
                               ('sourcekitd',sourcekitd,Path(sourcekitd['path']))]:
        if not path.is_file() or 'sha256:'+sha(path)!=record['sha256']:
            raise ValueError(f'{label} executable hash mismatch')
    version=subprocess.check_output([compiler['executablePath'],'--version'],env=env,text=True)
    if version.strip()!=compiler['version'].strip(): raise ValueError('compiler version mismatch')
    version_xcode=subprocess.check_output(['xcodebuild','-version'],env=env,text=True).strip()
    if version_xcode!=tool['xcodebuildVersion']: raise ValueError('Xcode version mismatch')
    modules={}
    for item in link['interfaces']:
        module=item['module']; interface=Path(item['path'])
        if not interface.is_file() or 'sha256:'+sha(interface)!=item['sha256']:
            raise ValueError(f'{module} live interface hash mismatch')
        req=ROOT/item['indexRequest']; raw=ROOT/item['indexOutput']
        if 'sha256:'+sha(req)!=item['indexRequestSha256'] or 'sha256:'+sha(raw)!=item['indexOutputSha256']:
            raise ValueError(f'{module} SourceKit request/output hash mismatch')
        req_text=req.read_text()
        if not validate_request_binding(req_text,interface=str(interface),sdk=str(sdk),target=TARGET,module=module):
            raise ValueError(f'{module} SourceKit request identity mismatch')
        if item['requestIdentity']!={'sourcefile':str(interface),'sdk':'MacOSX27.0.sdk','target':TARGET,'moduleName':module}:
            raise ValueError(f'{module} evidence request identity mismatch')
        modules[module]={'interfacePath':str(interface),'interfaceSha256':item['sha256'],
          'requestPath':str(req.relative_to(ROOT)),'requestSha256':item['indexRequestSha256'],
          'rawOutputPath':str(raw.relative_to(ROOT)),'rawOutputSha256':item['indexOutputSha256'],
          'requestIdentity':item['requestIdentity'],'rawEntities':parse_index_declarations(raw)}
    return {'sourceLinkPath':str(link_path.relative_to(ROOT)),'sourceLinkSha256':'sha256:'+sha(link_path),
      'auditHash':link['pinnedInputs']['auditHash'],'xcodebuildVersion':version_xcode,
      'compiler':compiler,'sourcekitLsp':lsp,'sourcekitd':sourcekitd,
      'sdkPath':str(sdk),'sdkSettingsPath':str(sdk_settings),'sdkSettingsSha256':'sha256:'+sha(sdk_settings),
      'target':TARGET,'modules':modules}


def build_bridge_evidence()->dict:
    link_path=SPIKE/'link-evidence.json'; link=json.loads(link_path.read_text())
    seed_path=HERE/'access-evidence.json'; receipt_path=HERE/'run-receipt.json'
    if sha(seed_path)!=EXPECTED_SEED_SHA256: raise ValueError('seed access evidence hash changed')
    if sha(receipt_path)!=EXPECTED_RECEIPT_SHA256: raise ValueError('seed run receipt hash changed')
    bindings=validate_bindings(link)
    accepted=[]; held=[]
    for row in link['rows']:
        if row.get('linkHoldReason')!='expected-access-unavailable': continue
        module=row['module']; interface=Path(bindings['modules'][module]['interfacePath'])
        line_scopes=parse_lexical_scopes(interface,module)[row['line']]
        try:
            result=validate_case_link(row,bindings['modules'][module]['rawEntities'],line_scopes,
              module=module,raw_entity_module=module,
              live_interface_sha256=bindings['modules'][module]['interfaceSha256'].removeprefix('sha256:'),
              request_is_exact=bindings['modules'][module]['requestIdentity']==row_identity(bindings['modules'][module]))
            accepted.append(result)
        except ValueError as error:
            held.append({'module':module,'line':row['line'],'name':row['name'],'reason':str(error)})
    if held or len(accepted)!=51: raise ValueError(f'bridge did not validate exact 51: {len(accepted)} accepted; held={held[:5]}')
    return {'kind':'compiler-enum-case-access-bridge','version':1,
      'validatorSourceSha256':'sha256:'+sha(Path(__file__).resolve()),
      'seedAccessEvidencePath':str(seed_path.relative_to(ROOT)),
      'seedAccessEvidenceSha256':'sha256:'+sha(seed_path),
      'seedRunReceiptPath':str(receipt_path.relative_to(ROOT)),
      'seedRunReceiptSha256':'sha256:'+sha(receipt_path),
      'bindings':{k:v for k,v in bindings.items() if k!='modules'},
      'modules':{m:{k:v for k,v in rec.items() if k!='rawEntities'} for m,rec in bindings['modules'].items()},
      'summary':{'sourceRows':51,'validatedRows':len(accepted),'heldRows':len(held),
        'uniqueCompilerUsrs':len({r['usr'] for r in accepted})},'rows':accepted}


def row_identity(module_binding:dict)->dict:
    return module_binding['requestIdentity']


def main()->None:
    out=build_bridge_evidence()
    dest=HERE/'derived-access-bridge.json'
    dest.write_text(json.dumps(out,sort_keys=True,separators=(',',':'))+'\n')
    print(json.dumps({'output':str(dest.relative_to(ROOT)),'rows':out['summary']['validatedRows'],
      'sha256':'sha256:'+sha(dest)}))
if __name__=='__main__': main()
