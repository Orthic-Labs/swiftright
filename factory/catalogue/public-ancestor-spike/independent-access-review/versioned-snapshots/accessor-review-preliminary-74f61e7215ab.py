#!/usr/bin/env python3
"""Bounded observed accessors: pinned actual inputs, snapshot & semantic controls."""
import collections,copy,hashlib,importlib.util,json,re
from pathlib import Path
HERE=Path(__file__).resolve().parent
BASE=HERE.parent
ROOT=HERE.parents[3]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p,name):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def main():
 data=(BASE/'compiler_children.py').read_bytes();pin=hashlib.sha256(data).hexdigest();snapshot=HERE/'versioned-snapshots'/('compiler-children-preliminary-'+pin[:12]+'.py')
 assert not snapshot.exists() or snapshot.read_bytes()==data;snapshot.write_bytes(data)
 c=load(snapshot,'frozen_accessors');h=load(ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py','pinned_raw_parser');assert sha(ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py')=='83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5'
 attr_parser=load(HERE/'review_final_access.py','independent_attrs').attributes_from_text
 artifact=BASE/'public-ancestor-evidence-v1.json';artifact_bytes=artifact.read_bytes();a=json.loads(artifact_bytes);inputs=a['inputs'];pins={};raw={}
 for key in ['trees','processResults',*[m+':'+kind for m in ['SwiftUI','SwiftUICore'] for kind in ['index','source','destructorAST']]]:
  p=Path(inputs[key]['path']);data=p.read_bytes();observed=hashlib.sha256(data).hexdigest();pins[key]={'path':str(p),'sha256':'sha256:'+observed,'artifactDescriptorSha256':inputs[key]['sha256']};raw[key]=data.decode()
  if key in {'trees','processResults'}:
   frozen=HERE/'versioned-snapshots'/(key+'-'+observed[:12]+'.txt');assert not frozen.exists() or frozen.read_bytes()==data;frozen.write_bytes(data);pins[key]['snapshotPath']=str(frozen.relative_to(ROOT))
  else:assert 'sha256:'+observed==inputs[key]['sha256']
 trees=h.trees(raw['trees']);rows={tuple(r['key']):r for r in a['resolution']['rows']};contexts={};counts=collections.Counter();families=collections.Counter();restrictions=collections.Counter();examples={};identities=[];duplicate_positions={}
 selected={m:{x.split(':')[1] for x in json.loads(raw['processResults'])[m]['run']['stdout'].splitlines()} for m in ['SwiftUI','SwiftUICore']}
 for m in ['SwiftUI','SwiftUICore']:
  source=raw[m+':source'];lines=source.splitlines();model=h.source_model(source);entities=h.entities(raw[m+':index']);nodes=c.ast_nodes(raw[m+':destructorAST']);contexts[m]=(lines,model)
  branches={};stack=[]
  for number,text in enumerate(lines,1):
   stripped=text.strip()
   if stripped.startswith('#if '):stack.append(number)
   elif stripped.startswith('#elseif ') or stripped=='#else':stack[-1]=number
   elif stripped=='#endif':stack.pop()
   branches[number]=stack[:]
  for e in entities:
   if e['kind'] not in {'source.lang.swift.decl.function.accessor.getter','source.lang.swift.decl.function.accessor.setter'}:continue
   context=e['sourcekitContext'][-1];parents=[p for p in entities if all(p.get(k)==context.get(k) for k in ['kind','name','usr','line','column'])];assert parents and all(x==parents[0] for x in parents);parent=parents[0]
   positions=[x for x in entities if (x['line'],x['column'])==(e['line'],e['column'])]
   if len(positions)!=1:
    assert m=='SwiftUI' and e['line'] in {4081,5534,9718,23751,32823} and len(positions)==2 and positions[0]==positions[1]
    duplicate_positions[str(e['line'])]=2
   family='get' if e['kind'].endswith('.getter') else 'set';assert re.match(family+r'\b',lines[e['line']-1][e['column']-1:]);families[family]+=1
   node=c.accessor(e,parent,nodes,trees,inputs[m+':source']['path'],source);counts[node['access']]+=1
   child=trees[e['usr']]['children'];pt=trees[parent['usr']]['children']
   if child[0]['kind']=='Static':assert pt[0]['kind']=='Static';child=child[0]['children'];pt=pt[0]['children']
   assert len(child)==len(pt)==1 and child[0]['kind']==('Getter' if family=='get' else 'Setter') and child[0]['children']==pt
   key=(m,'arm64e-apple-macos.swiftinterface',parent['line'],parent['name'].strip('`').split('(')[0]);parentrow=rows[key]
   assert all(str(q) in selected[m] for q in branches[e['line']])
   assert model[e['line']]['conditions']==model[parent['line']]['conditions']
   if node['access'] in {'public','open'} and parentrow.get('usr'):
    assert parentrow['usr']==parent['usr'];restrictions[parentrow['status']]+=1
   examples.setdefault(node['access'],(m,e,parent,node,nodes,source));identities.append({'module':m,'usr':e['usr'],'parentUsr':parent['usr'],'sourceKey':list(key),'rawLine':e['line'],'rawColumn':e['column'],'family':family,'typedAccess':node['access'],'parentStatus':parentrow['status'],'inheritedRestrictions':parentrow.get('attributedRestrictions',[])})
 assert len(identities)==2190 and counts=={'public':2000,'open':18,'internal':108,'package':64}
 # Reconstruct own/physical-extension/resolved nominal restrictions directly source for every public qualified parent.
 for identity in identities:
  if identity['typedAccess'] not in {'public','open'}:continue
  parentrow=rows[tuple(identity['sourceKey'])]
  if not parentrow.get('usr'):continue
  m=identity['module'];line=identity['sourceKey'][2];lines,model=contexts[m]
  assert parentrow['kind'] in {'var','let','subscript'}
  for ancestor in (parentrow.get('owner') or {}).get('chain',[]):
   text=contexts[ancestor['module']][0][ancestor['line']-1]
   for at in attr_parser(text):text=text.replace(at,'',1)
   assert re.search(r'\b(public|open)\b',text.split(ancestor['kind'],1)[0]),identity['usr']
  for ancestor in model[line]['scopes']:
   if ancestor['kind']!='extension':continue
   text=lines[ancestor['line']-1]
   for at in attr_parser(text):text=text.replace(at,'',1)
   assert not re.search(r'\b(private|fileprivate|internal|package)\b',text.split('extension',1)[0]),identity['usr']
  attrcontexts=[('declaration',m,line)]+[('physical-extension',m,q['line']) for q in model[line]['scopes'] if q['kind']=='extension']+[('resolved-nominal-ancestor',q['module'],q['line']) for q in (parentrow.get('owner') or {}).get('chain',[])]
  derived=[]
  for role,am,n in attrcontexts:
   als,amd=contexts[am];texts=[(n,als[n-1])];cursor=n-1
   while cursor>0 and als[cursor-1].strip().startswith('@') and amd[cursor]['scopes']==amd[n]['scopes'] and amd[cursor]['conditions']==amd[n]['conditions']:
    residual=als[cursor-1]
    for at in attr_parser(residual):residual=residual.replace(at,'',1)
    if residual.strip():break
    texts.insert(0,(cursor,als[cursor-1]));cursor-=1
   for an,text in texts:
    for at in attr_parser(text):
     category='documentation-hidden' if re.fullmatch(r'@_documentation\(visibility: (private|internal)\)',at) else 'macOS-unavailable' if re.fullmatch(r'@_?available\((?:macOS|\*), unavailable(?:,.*)?\)',at) else 'spi' if at.startswith('@_spi(') else None
     if category:derived.append({'category':category,'role':role,'module':am,'ownerLine':n,'attribute':{'line':an,'text':at}})
  assert derived==identity['inheritedRestrictions'],identity['usr']
 # Target semantic joins after passing immutable provenance: each reason must be reached.
 m,e,p,n,nodes,source=examples['internal'];faults=[]
 def reject(name,entity=e,parent=p,ast=nodes,tree=trees,reason=None):
  try:c.accessor(entity,parent,ast,tree,inputs[m+':source']['path'],source)
  except ValueError as ex:
   assert reason is None or reason in str(ex),(name,str(ex));faults.append({'name':name,'reason':str(ex),'rejected':True})
  else:raise AssertionError('accepted '+name)
 for field,value in [('kind','source.lang.swift.decl.enum'),('usr','s:WrongParent'),('line',p['line']+1),('column',p['column']+1)]:
  bad=copy.deepcopy(p);bad[field]=value;reject('raw-parent-'+field,parent=bad,reason='raw exact parent context')
 bad=copy.deepcopy(p);bad['kind']='source.lang.swift.decl.enum';be=copy.deepcopy(e);be['sourcekitContext'][-1]['kind']=bad['kind'];reject('coherent-parent-wrong-kind',entity=be,parent=bad,reason='raw/AST parent family')
 other_usr=next(usr for usr,tree in trees.items() if usr!=p['usr'] and tree['children'] and tree['children'][0]['kind']=='Static' and tree['children'][0]['children'] and tree['children'][0]['children'][0]['kind']=='Variable')
 bad=copy.deepcopy(p);bad['usr']=other_usr;be=copy.deepcopy(e);be['sourcekitContext'][-1]['usr']=other_usr;reject('coherent-parent-wrong-known-USR',entity=be,parent=bad,reason='exact family/full parent tree')
 other_child=next(usr for usr,tree in trees.items() if usr!=e['usr'] and tree['children'] and tree['children'][0]['kind']=='Static' and tree['children'][0]['children'] and tree['children'][0]['children'][0]['kind']=='Getter' and tree['children'][0]['children'][0]['children']!=trees[p['usr']]['children'][0]['children'])
 be=copy.deepcopy(e);be['usr']=other_child;reject('wrong-known-child-USR',entity=be,reason='exact family/full parent tree')
 for field,value in [('kind','source.lang.swift.decl.function.accessor.setter'),('usr','s:WrongChild'),('line',e['line']+1),('column',e['column']+1)]:
  bad=copy.deepcopy(e);bad[field]=value;reject('raw-child-'+field,entity=bad)
 badnodes=copy.deepcopy(nodes);target=next(x for x in badnodes if x==n);target['access']='public';reject('derived-node-access',ast=badnodes,reason='fields disagree with actual raw header')
 badnodes=copy.deepcopy(nodes);target=next(x for x in badnodes if x==n);target['owners'][-1]['access']='public';reject('derived-owner-access',ast=badnodes,reason='ancestor fields disagree')
 badtree=copy.deepcopy(trees);roots=badtree[e['usr']]['children'];roots=roots[0]['children'] if roots[0]['kind']=='Static' else roots;roots[0]['kind']='Setter';reject('wrong-full-getter-tree',tree=badtree,reason='exact family/full parent tree')
 assert artifact.read_bytes()==artifact_bytes
 report={'kind':'independent-observed-accessor-preliminary-review','reviewerSourceSha256':sha(Path(__file__)),'snapshotPath':str(snapshot.relative_to(ROOT)),'snapshotSha256':pin,'artifactSha256':hashlib.sha256(artifact_bytes).hexdigest(),'actualInputPins':pins,'identicalObservedProjectedGetterPairs':duplicate_positions,'observedRecords':len(identities),'accessCounts':dict(counts),'familyCounts':dict(families),'qualifiedPublicChildrenByInheritedParentStatus':dict(restrictions),'everyObservedAccessorHasExplicitTypedAstAccess':True,'sourceTokensPositionsKindsParentContextsFullTreesChecked':True,'everyQualifiedPublicChildInheritsActualSourceRestrictions':True,'qualifiedParentSourceKindAndPublicAncestorExtensionCapsChecked':True,'publicChildrenWithUnqualifiedParentRemainHeld':sum(counts[k] for k in ['public','open'])-sum(restrictions.values()),'semanticFaults':faults,'scope':'Only 2190 observed getter/setter raw records; full F1 freeze review follows.','promotionsMade':0}
 (HERE/'observed-accessor-preliminary-review.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(sha(HERE/'observed-accessor-preliminary-review.json'))
if __name__=='__main__':main()
