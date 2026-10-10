#!/usr/bin/env python3
"""Inspect compiler-reported effective access for held enum-case rows."""
import hashlib, json, re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
BASE=ROOT/'factory/catalogue/compiler-cursor-spike'
OUT=Path(__file__).resolve().parent
LINK=json.loads((BASE/'link-evidence.json').read_text())
INTERFACES={x['module']:Path(x['path']) for x in LINK['interfaces']}
INTERFACE_HASHES={x['module']:x['sha256'] for x in LINK['interfaces']}
RAW={
 'SwiftUI':BASE/'index-interface-output.txt',
 'SwiftUICore':BASE/'index-core-output.txt',
}
DECL_PREFIX='source.lang.swift.decl.'
CONTAINERS={
 'source.lang.swift.decl.extension', 'source.lang.swift.decl.struct',
 'source.lang.swift.decl.enum','source.lang.swift.decl.protocol',
 'source.lang.swift.decl.class','source.lang.swift.decl.actor',
}
def parse(path):
    result=[]; stack=[]
    for line in path.read_text().splitlines():
        m=re.match(r'^(\s*)\{$',line)
        if m: stack.append({'indent':len(m.group(1)),'fields':{}}); continue
        m=re.match(r'^(\s*)\}(?:,)?$',line)
        if m:
            indent=len(m.group(1))
            while stack and stack[-1]['indent']>=indent:
                fields=stack.pop()['fields']
                if str(fields.get('kind','')).startswith(DECL_PREFIX) and all(k in fields for k in ('name','usr','line')):
                    fields['sourcekitContext']=[{'kind':p['fields'].get('kind'),'name':p['fields'].get('name')}
                        for p in stack if (str(p['fields'].get('kind','')).startswith('source.lang.swift.decl.extension')
                            or p['fields'].get('kind') in CONTAINERS)]
                    result.append(fields)
            continue
        m=re.match(r'^(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?)(?:,)?$',line)
        if m and stack and stack[-1]['indent']+2==len(m.group(1)):
            _,key,value=m.groups()
            if value.startswith('"'): value=json.loads(value)
            elif value.isdigit(): value=int(value)
            stack[-1]['fields'][key]=value
    return result

def norm_name(n): return str(n).strip('`').split('(',1)[0]
def ctx_names(cs): return [str(x.get('name','')).split('.')[-1].split('<',1)[0] for x in cs]
def owner_enum(lines, line_number, context_name):
    pattern=re.compile(r'^\s*(?:(?:@\w+)(?:\([^)]*\))?\s+)*(?:(public|open|package|internal|fileprivate|private)\s+)?(?:indirect\s+)?enum\s+`?'+re.escape(context_name)+r'\b')
    for idx in range(line_number-2,-1,-1):
        match=pattern.match(lines[idx])
        if match:
            return {'line':idx+1,'declaration':lines[idx].strip(),'explicitAccess':match.group(1) or None}
    return None
entities={m:parse(p) for m,p in RAW.items()}
for m,src in INTERFACES.items():
    expected=next(x for x in LINK['interfaces'] if x['module']==m)['sha256']
    live='sha256:'+hashlib.sha256(src.read_bytes()).hexdigest()
    assert live==expected, (m,live,expected)
    INTERFACE_HASHES[m]=live
rows=[]
interface_lines={m:INTERFACES[m].read_text().splitlines() for m in INTERFACES}
for r in LINK['rows']:
    if r['linkHoldReason']!='expected-access-unavailable': continue
    want_ctx=[str(x).split('.')[-1].split('<',1)[0] for x in r['context']]
    candidates=[e for e in entities[r['module']] if e['line']==r['line'] and e['kind']=='source.lang.swift.decl.enumelement'
      and norm_name(e['name'])==r['name'].strip('`').split('(',1)[0]
      and ctx_names(e.get('sourcekitContext',[]))==want_ctx]
    rows.append({
      'module':r['module'],'interface':r['interface'],'sourceHash':INTERFACE_HASHES[r['module']],'line':r['line'],
      'context':r['context'],'name':r['name'],'signature':r['signature'],
      'lexicalOwnerEnum':owner_enum(interface_lines[r['module']],r['line'],r['context'][-1]),
      'auditRowKey':r['auditRowKey'],'rawEntityCount':len(candidates),
      'entities':[{'kind':e['kind'],'name':e['name'],'usr':e['usr'],'line':e['line'],'column':e.get('column'),
                   'effectiveAccess':e.get('effective_access'),'context':e.get('sourcekitContext')}
                  for e in candidates],
    })
fixture_entities=parse(OUT/'index-fixture-output.txt')
fixture_access_controls=[]
for line,name in [(2,'visible'),(6,'hidden'),(10,'hidden'),(15,'visible'),(19,'hidden'),(23,'hidden'),(27,'hidden')]:
    matches=[e for e in fixture_entities if e.get('line')==line and e.get('name')==name and e.get('kind')=='source.lang.swift.decl.enumelement']
    assert len(matches)==1,(line,name,len(matches))
    fixture_access_controls.append({'line':line,'case':name,'usr':matches[0]['usr'],
      'effectiveAccess':str(matches[0].get('effective_access','')).rsplit('.',1)[-1],
      'context':matches[0].get('sourcekitContext',[])})
assert all(r['lexicalOwnerEnum'] and r['lexicalOwnerEnum']['explicitAccess'] in ('public','open') for r in rows)
assert all(r['rawEntityCount']==1 and len(r['entities'][0]['usr'])>0 and
           r['entities'][0]['effectiveAccess']=='source.decl.effective_access.public' for r in rows)
print('rows',len(rows),'raw exact candidates',sum(r['rawEntityCount'] for r in rows))
from collections import Counter
print('counts',Counter((r['rawEntityCount'], r['entities'][0].get('effectiveAccess') if r['rawEntityCount']==1 else None) for r in rows))
print('nonunique/access missing',[(r['module'],r['line'],r['name'],r['rawEntityCount'],r['entities']) for r in rows if r['rawEntityCount']!=1 or not r['entities'][0].get('effectiveAccess')])
(OUT/'access-evidence.json').write_text(json.dumps({
 'kind':'compiler-enum-case-effective-access-evidence','version':1,
 'sourceLinkEvidenceSha256':'sha256:'+hashlib.sha256((BASE/'link-evidence.json').read_bytes()).hexdigest(),
 'rawIndexResponseSha256':{m:'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest() for m,p in RAW.items()},
 'fixtureIndexOutputSha256':'sha256:'+hashlib.sha256((OUT/'index-fixture-output.txt').read_bytes()).hexdigest(),
 'fixtureAccessControls':fixture_access_controls,
 'summary':{'rows':len(rows),'uniqueExactRawPublicEntities':sum(r['rawEntityCount']==1 and r['entities'][0]['effectiveAccess']=='source.decl.effective_access.public' for r in rows),
   'distinctCompilerUsrs':len({r['entities'][0]['usr'] for r in rows})},
 'rows':rows,
},sort_keys=True,separators=(',',':'))+'\n')
