#!/usr/bin/env python3
"""Independent access/attribute verification; durable output only in review directory."""
import collections
import hashlib
import importlib.util
import json
import re
from pathlib import Path
from inspect_access_facts import ROOT,HERE,module

BASE=HERE.parent
ARTIFACT=BASE/'public-ancestor-evidence-v1.json'
def sha(path):return 'sha256:'+hashlib.sha256(path.read_bytes()).hexdigest()
def attributes_from_text(text):
 result=[];cursor=0
 while cursor<len(text):
  match=re.search(r'@\w+',text[cursor:])
  if not match:break
  start=cursor+match.start();end=cursor+match.end()
  if end<len(text) and text[end]=='(':
   depth=0;quoted=False;escaped=False
   while end<len(text):
    char=text[end]
    if quoted:
     if escaped:escaped=False
     elif char=='\\':escaped=True
     elif char=='"':quoted=False
    elif char=='"':quoted=True
    elif char=='(':depth+=1
    elif char==')':
     depth-=1
     if depth==0:end+=1;break
    end+=1
  result.append(text[start:end]);cursor=end
 return result

def main():
 artifact_bytes=ARTIFACT.read_bytes();guard_path=BASE/'exact_public_ancestor.py';guard_pin=sha(guard_path);evidence=json.loads(artifact_bytes);helper=module();resolution=evidence['resolution'];sources={};models={};index={};selected=resolution['compilerSelectedBranches'];branch_lines={};assert set(selected)=={'SwiftUI','SwiftUICore'}
 for key,d in evidence['inputs'].items():assert sha(Path(d['path']))==d['sha256'],key
 processes=json.loads(Path(evidence['inputs']['processResults']['path']).read_text())
 assert selected=={name:[line.split(':')[1] for line in processes[name]['run']['stdout'].splitlines()] for name in ('SwiftUI','SwiftUICore')}
 for name in ('SwiftUI','SwiftUICore'):
  sources[name]=Path(evidence['inputs'][name+':source']['path']).read_text().splitlines();models[name]=helper.source_model('\n'.join(sources[name])+'\n');index[name]=helper.entities(Path(evidence['inputs'][name+':index']['path']).read_text())
 for name,lines in sources.items():
  stack=[];branch_lines[name]={}
  for number,text in enumerate(lines,1):
   stripped=text.strip()
   if stripped.startswith('#if '):stack.append(number)
   elif stripped.startswith('#elseif ') or stripped=='#else':stack[-1]=number
   elif stripped=='#endif':stack.pop()
   branch_lines[name][number]=stack[:]
 def active(name,line):return all(str(branch) in set(selected[name]) for branch in branch_lines[name][line])
 def source_attributes(name,line):
  texts=[(line,sources[name][line-1])];cursor=line-1
  while cursor>0 and sources[name][cursor-1].strip().startswith('@') and models[name][cursor]['scopes']==models[name][line]['scopes'] and models[name][cursor]['conditions']==models[name][line]['conditions']:
   previous=sources[name][cursor-1]
   residual=previous
   for attr in attributes_from_text(previous):residual=residual.replace(attr,'',1)
   if residual.strip():break
   texts.insert(0,(cursor,previous));cursor-=1
  result=[]
  for number,text in texts:
   for expression in attributes_from_text(text):
    category=None
    if expression in {'@_documentation(visibility: private)','@_documentation(visibility: internal)'}:category='documentation-hidden'
    if re.fullmatch(r'@_?available\((?:macOS|\*), unavailable(?:,.*)?\)',expression):category='macOS-unavailable'
    if expression.startswith('@_spi('):category='spi'
    if category:result.append((number,expression,category))
  return result
 counts=collections.Counter();faults=[];checked=0;nonpublic_rawpublic=[]
 for row in resolution['rows']:
  name,_,line,decl=row['key'];status=row['status']
  if status=='excluded-nonpublic-source':
   matches=[e for e in index[name] if e['line']==line and e['name'].strip('`').split('(')[0]==decl and e.get('effective_access')=='source.decl.effective_access.public' and not e.get('is_implicit')]
   if matches:nonpublic_rawpublic.append(row['key'])
  if status not in {'eligible-compiler-mapped','public-compiler-mapped-documentation-hidden','public-compiler-mapped-attributed-unavailable'}:continue
  checked+=1;counts[status]+=1;assert row['effectivePublic'] is True and active(name,line)
  matches=[e for e in index[name] if e==row['rawEntity']];assert len(matches) in {1,2} and row['rawEntity']['effective_access']=='source.decl.effective_access.public',row['key']
  contexts=[('declaration',name,line)]
  contexts.extend(('physical-extension',name,x['line']) for x in models[name][line]['scopes'] if x['kind']=='extension')
  contexts.extend(('resolved-nominal-ancestor',x['module'],x['line']) for x in (row.get('owner') or {}).get('chain',[]))
  for ancestor in (row.get('owner') or {}).get('chain',[]):
   owner_text=sources[ancestor['module']][ancestor['line']-1]
   for attr in attributes_from_text(owner_text):owner_text=owner_text.replace(attr,'',1)
   prefix=owner_text.split(ancestor['kind'],1)[0]
   assert re.search(r'\b(public|open)\b',prefix),row['key']
  for scope in models[name][line]['scopes']:
   if scope['kind']=='extension':
    extension_text=sources[name][scope['line']-1]
    for attr in attributes_from_text(extension_text):extension_text=extension_text.replace(attr,'',1)
    assert not re.search(r'\b(private|fileprivate|internal|package)\b',extension_text.split('extension',1)[0]),row['key']
  actual=[]
  for role,owner_module,owner_line in contexts:
   assert active(owner_module,owner_line)
   for attr_line,text,category in source_attributes(owner_module,owner_line):actual.append({'category':category,'role':role,'module':owner_module,'ownerLine':owner_line,'attribute':{'line':attr_line,'text':text}})
  assert actual==row['attributedRestrictions'],(row['key'],actual,row['attributedRestrictions'])
  expected='public-compiler-mapped-attributed-unavailable' if any(x['category']=='macOS-unavailable' for x in actual) else 'public-compiler-mapped-documentation-hidden' if any(x['category']=='documentation-hidden' for x in actual) else 'eligible-compiler-mapped'
  assert status==expected,(row['key'],status,expected)
  if row['explicitAccess'] is None:
   assert row['accessRule']=='protocol/enum/public-extension inherited access'
   scopes=models[name][line]['scopes'];assert scopes
   parent=scopes[-1];text=sources[name][parent['line']-1]
   assert (parent['kind']=='protocol' and row['kind'] in {'func','var','subscript','init','associatedtype','typealias'}) or (parent['kind']=='enum' and row['kind']=='case') or (parent['kind']=='extension' and re.search(r'\b(public|open)\s+extension\b',text)),row['key']
 assert not nonpublic_rawpublic,nonpublic_rawpublic
 assert ARTIFACT.read_bytes()==artifact_bytes and sha(guard_path)==guard_pin,'review inputs changed during verification'
 report={'kind':'independent-bounded-access-review','artifactSha256':'sha256:'+hashlib.sha256(artifact_bytes).hexdigest(),'guardSha256':guard_pin,'dependencies':evidence['dependencies'],'reviewerSourceSha256':sha(Path(__file__)),'checkedPublicRawIdentityRows':checked,'byCheckedStatus':dict(counts),'excludedNonpublicWithMatchingExplicitPublicRawIdentity':nonpublic_rawpublic,'allActiveInheritedOwnExtensionNominalRestrictionsSourceEqual':True,'allImplicitAccessFamiliesProved':True,'unsupportedCompilerHiddenClaims':0,'criterion':'effective-public access & attributed hidden eligibility only','promotionsMade':0}
 output=HERE/'final-access-review.json';output.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report))
if __name__=='__main__':main()
