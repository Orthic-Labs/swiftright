#!/usr/bin/env python3
"""Review-only exact five-row guard. Inputs are reconstructed, never self-attested."""
from __future__ import annotations
import functools
import hashlib
import json
import re
from pathlib import Path
from typing import Any
from duplicate_identity_validator import digest_bytes, parse_demangle_tree

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SDK = '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk'
SOURCE = Path(SDK + '/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface')
LINK = ROOT / 'factory/catalogue/compiler-cursor-spike/link-evidence.json'
REQUEST = ROOT / 'factory/catalogue/compiler-cursor-spike/request-index-interface.yaml'
FROZEN = ROOT / 'factory/catalogue/compiler-cursor-spike/index-interface-output.txt'
PINS = {
 'link': 'sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec',
 'source': 'sha256:155b00c7d8fa9e9696b96b4bd3291b4c910207b480025d13ba6482f7b9940d38',
 'request': 'sha256:91ffbe06f6dc3e89074a5daa5d43e9e345e4903b11d70fc5d961601c159d6764',
 'response': 'sha256:352c81a020cd442aea487f0d74998f29b27d550b6958fd35582e4e14b3c1ef34',
 'demangle': 'sha256:bb47e5aecbf8c2d81a415daae7570d0b7b121d48ffa657e738daab789066f64c',
 'demangleTool': 'sha256:ae7da66c8a56fb3b90817c10eb816c82e25bf7a26ae0158effbda223f7f0fefe',
}
SCOPES = {4080: ('ToggleStyleConfiguration',4067),5533: ('DisclosureGroupStyleConfiguration',5507),9717: ('ReferenceFileDocumentConfiguration',9703),23750: ('FileDocumentConfiguration',23734),32822: ('DatePickerStyleConfiguration',32806)}
CONDITION = 'compiler(>=5.3) && $TildeSendable'

@functools.lru_cache(maxsize=32)
def _file_digest(path: str, size: int, mtime: int) -> str:
 return digest_bytes(Path(path).read_bytes())
def file_digest(path: Path) -> str:
 stat = path.stat()
 return _file_digest(str(path), stat.st_size, stat.st_mtime_ns)

def scalar(value: str) -> Any:
 value = value.rstrip(',')
 if value.startswith('"'): return json.loads(value)
 if value.isdigit(): return int(value)
 return value

@functools.lru_cache(maxsize=2)
def reconstruct_response(text: str) -> tuple[dict[str, Any], ...]:
 """Read every dictionary, retain exact byte intervals & declaration ancestry."""
 stack = []; found = []; offset = 0
 for line in text.splitlines(keepends=True):
  stripped = line.rstrip('\n')
  opening = re.fullmatch(r'( *)\{', stripped)
  closing = re.fullmatch(r'( *)\},?', stripped)
  if opening:
   stack.append({'indent':len(opening[1]),'offset':offset,'fields':{}})
  elif closing:
   if not stack or stack[-1]['indent'] != len(closing[1]): raise ValueError('unbalanced dictionary')
   obj = stack.pop(); fields = obj['fields']
   if str(fields.get('kind','')).startswith('source.lang.swift.decl.'):
    context = [{k:p['fields'][k] for k in ('kind','name','usr')} for p in stack
      if str(p['fields'].get('kind','')).startswith('source.lang.swift.decl.') and all(k in p['fields'] for k in ('kind','name','usr'))]
    entity = dict(fields); entity['sourcekitContext'] = context
    if 'is_implicit' in entity: entity['is_implicit'] = bool(entity['is_implicit'])
    block = text[obj['offset']:offset+len(line)]
    found.append({'entity':entity,'record': {'line':fields.get('line'),'name':fields.get('name'),'kind':fields.get('kind'),'usr':fields.get('usr'),'text':block,'sha256':digest_bytes(block.encode()),'bytes':len(block.encode())},'startByte':obj['offset'],'endByte':offset+len(line)})
  else:
   field = re.fullmatch(r'( *)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*)', stripped)
   if field and stack and len(field[1]) == stack[-1]['indent']+2:
    if field[2] in stack[-1]['fields']: raise ValueError('duplicate key')
    stack[-1]['fields'][field[2]] = scalar(field[3])
  offset += len(line)
 if stack: raise ValueError('unclosed dictionary')
 return tuple(found)

@functools.lru_cache(maxsize=16)
def lexical_identity(text: str, line: int, name: str) -> dict[str, Any]:
 """Reconstruct enclosing nominal brace path & conditional arm from SDK text."""
 braces = []; conditions = []; identity = None; declarations = []
 for number, original in enumerate(text.splitlines(),1):
  # Interface comments & string literals cannot introduce scope braces/directives.
  clean = re.sub(r'"(?:\\.|[^"\\])*"','""',original.split('//',1)[0]); stripped = clean.strip()
  if stripped.startswith('#if '): conditions.append([stripped[4:],True])
  elif stripped == '#else':
   if not conditions: raise ValueError('unmatched else')
   conditions[-1][1] = False
  elif stripped.startswith('#elseif '):
   if not conditions: raise ValueError('unmatched elseif')
   conditions[-1] = [stripped[8:],False]
  elif stripped == '#endif':
   if not conditions: raise ValueError('unmatched endif')
   conditions.pop()
  else:
   scope = [b for b in braces if b['name'] is not None]
   if number == line: identity = {'scope':scope.copy(),'conditions':[x[:] for x in conditions], 'lineText':original}
   if re.search(r'\bvar\s+'+re.escape(name)+r'\s*:',clean):
    declarations.append({'line':number,'scope':scope.copy(),'conditions':[x[:] for x in conditions]})
   owner = re.search(r'\b(struct|class|enum|protocol|extension)\s+([\w.]+)',clean)
   for token in re.finditer(r'[{}]',clean):
    if token[0] == '{':
     braces.append({'name':owner[2] if owner else None,'kind':owner[1] if owner else None,'line':number})
     owner = None
    elif braces: braces.pop()
    else: raise ValueError('unmatched brace')
 if identity is None: raise ValueError('missing line')
 identity['uniqueActiveLines'] = [d['line'] for d in declarations if d['scope']==identity['scope'] and d['conditions']==identity['conditions']]
 return identity

def full_owner_identity(tree: dict[str, Any] | None, scope: str, name: str) -> bool:
 if not tree or tree.get('kind')!='Global' or tree.get('text') is not None or len(tree.get('children',[]))!=1: return False
 variable=tree['children'][0]
 if variable.get('kind')!='Variable' or variable.get('text') is not None: return False
 children=variable.get('children',[])
 if [node.get('kind') for node in children]!=['Structure','Identifier','Type']: return False
 owner,identifier,type_node=children
 expected_owner={'kind':'Structure','text':None,'children':[{'kind':'Module','text':'SwiftUI','children':[]},{'kind':'Identifier','text':scope,'children':[]}]}
 return owner==expected_owner and identifier=={'kind':'Identifier','text':name,'children':[]} and type_node.get('text') is None and bool(type_node.get('children'))

@functools.lru_cache(maxsize=1)
def frozen() -> dict[str, Any]:
 for key,path in [('link',LINK),('source',SOURCE),('request',REQUEST),('response',FROZEN),('demangle',HERE/'usr-demangle.txt')]:
  if file_digest(path) != PINS[key]: raise ValueError('immutable '+key+' pin')
 link = json.loads(LINK.read_text()); rows = {}
 records = reconstruct_response(FROZEN.read_text())
 for row in link['rows']:
  if row.get('module')=='SwiftUI' and row.get('line') in SCOPES:
   line=row['line']; match=row['indexMatches'][0]; name=match['occurrences'][0]['name']
   pair=[r for r in records if r['entity'].get('line')==line]
   if len(pair)!=2 or pair[0]['record']!=pair[1]['record'] or pair[0]['entity']!=pair[1]['entity']: raise ValueError('frozen pair')
   if pair[0]['entity']['usr'] != match['usr']: raise ValueError('frozen usr')
   rows[line]={'link':row,'name':name,'pair':pair,'lexical':lexical_identity(SOURCE.read_text(),line,name),'tree':parse_demangle_tree((HERE/'usr-demangle.txt').read_text(),match['usr'])}
 for line,spec in rows.items():
  if not full_owner_identity(spec['tree'],SCOPES[line][0],spec['name']): raise ValueError('frozen full owner tree')
 if set(rows)!=set(SCOPES): raise ValueError('five row keys')
 return {'rows':rows,'toolchain':link['toolchainEvidence']}

def validate_duplicate_identity(row, raw_entities, raw_records, *, source_text, source_sha256, request_text, request_sha256, expected_request_sha256, response_sha256, expected_response_sha256, demangle_text, toolchain, expected_toolchain, source_path, raw_response_text=None):
 reasons=[]
 def check(ok, reason):
  if not ok: reasons.append(reason)
 try: trust=frozen()
 except (ValueError,OSError,KeyError) as error: return {'accepted':False,'reasons':['immutable-input:'+str(error)]}
 spec=trust['rows'].get(row.get('line'))
 if spec is None: return {'accepted':False,'reasons':['exact-five-key']}
 link=spec['link']; pair=spec['pair']; expected=pair[0]['entity']; scope,scope_line=SCOPES[row['line']]
 check(row.get('auditRowKey')==link['auditRowKey'] and row.get('signature')==link['signature'] and row.get('key')==['SwiftUI',link['interface'],row['line'],'var'],'frozen-row-signature-key')
 check(row.get('module')=='SwiftUI' and row.get('kind')=='var' and row.get('name')==spec['name'] and row.get('context')==link['context'],'exact-row')
 check(source_path==str(SOURCE),'source-path')
 check(source_sha256==PINS['source'] and row.get('sourceHash')==PINS['source'] and digest_bytes(source_text.encode())==PINS['source'],'source-bytes')
 check(request_sha256==expected_request_sha256==PINS['request'] and digest_bytes(request_text.encode())==PINS['request'],'request-bytes')
 check(response_sha256==expected_response_sha256==PINS['response'],'response-pin')
 if raw_response_text is None: raw_response_text=(HERE/'sourcekit-index-output.txt').read_text()
 check(digest_bytes(raw_response_text.encode())==PINS['response'],'response-bytes')
 check(toolchain==expected_toolchain==trust['toolchain'],'toolchain-identity')
 for entry in (trust['toolchain']['compiler'],trust['toolchain']['sourcekitLsp'],trust['toolchain']['sourcekitd']):
  check(file_digest(Path(entry.get('executablePath',entry.get('path'))))==entry['sha256'],'toolchain-bytes')
 check(file_digest(Path('/usr/bin/xcrun'))=='sha256:bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9','dispatcher-bytes')
 check(file_digest(Path(trust['toolchain']['compiler']['driverPath']))==trust['toolchain']['compiler']['sha256'],'driver-bytes')
 check(file_digest(Path(trust['toolchain']['compiler']['driverPath']).with_name('swift-demangle'))==PINS['demangleTool'],'demangle-tool-bytes')
 check(digest_bytes(demangle_text.encode())==PINS['demangle'] and file_digest(HERE/'exact-demangle.stdout')==PINS['demangle'],'demangle-bytes')
 check((HERE/'tilde-sendable-probe.swift').read_bytes()==b'#if compiler(>=5.3) && $TildeSendable\nprint("selected=active")\n#else\nprint("selected=inactive")\n#endif\n' and (HERE/'exact-branch.stdout').read_bytes()==b'selected=active\n','compiler-condition-proof')
 tree=parse_demangle_tree(demangle_text,expected['usr'])
 check(tree==spec['tree'] and full_owner_identity(tree,scope,spec['name']),'usr-full-tree')
 try:
  lex=lexical_identity(source_text,row['line'],spec['name'])
  check(lex==spec['lexical'],'source-lexical')
  check(lex['scope']==[{'name':scope,'kind':'struct','line':scope_line}] and row.get('scopeName')==scope and row.get('scopeLine')==scope_line and row.get('context')==[scope],'source-scope')
  check(lex['conditions']==[[CONDITION,True]] and row.get('activeCondition')==CONDITION and row.get('activeBranch') is True,'source-branch')
  check(lex['uniqueActiveLines']==[row['line']] and lex['lineText'].strip()==link['signature'] and row.get('sourceLine')==lex['lineText'],'unique-source-declaration')
 except (ValueError,KeyError,TypeError): reasons.append('source-lexical')
 check(len(raw_entities)==len(raw_records)==2,'cardinality')
 if len(raw_entities)==2:
  check(raw_entities[0]==raw_entities[1],'distinct-entities')
  for entity in raw_entities:
   for field in ('usr','kind','effective_access','name','line','column','sourcekitContext','is_implicit'):
    check(entity.get(field)==expected.get(field),'semantic-'+field)
   check(entity==expected,'entity-full-identity')
 if len(raw_records)==2:
  check(raw_records[0]==raw_records[1],'distinct-records')
 try:
  parsed=[x for x in reconstruct_response(raw_response_text) if x['entity'].get('line')==row['line']]
  check(parsed==pair,'response-cardinality-position-block-entity')
  check(raw_entities==[x['entity'] for x in parsed],'entities-response-binding')
  check(raw_records==[x['record'] for x in parsed],'records-response-binding')
 except (ValueError,KeyError,TypeError): reasons.append('response-parse')
 return {'accepted':not reasons,'reasons':list(dict.fromkeys(reasons))}

def duplicate_identity_accepts(*args,**kwargs): return validate_duplicate_identity(*args,**kwargs)['accepted']
