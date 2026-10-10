#!/usr/bin/env python3
"""Bounded effective-access facts from successful whole pinned SDK ASTs."""
import hashlib,json,re,shlex
from pathlib import Path
from collections import Counter
HERE=Path(__file__).resolve().parent
SEED=HERE.parent/'destructor-access-capture/destructor-access-evidence.json'
SEED_HASH='c4651161d825a44f24c4c90451160dae7e9f2f4a3ec9e9f8d160c38516c4fa86'
RAW=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/destructor-api-eligibility-proof/arm64-v2')
SDK=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk')
TOOL=Path('/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend')
TARGET='arm64-apple-macosx27.0'
ARCHIVE_HASH='e3ebc2f4b08c10178649308741efe786be2de823cfbfcf775b26dcb62d78c107'
RAW_PINS_HASH='bc471c74da8ac9ab452dd59ad7e9660a5450c99e4b0f7ba1bc270d1e72b7c99e'
def archive_manifest():
 path=HERE/'archive-manifest-v2.json'
 require(hashlib.sha256(path.read_bytes()).hexdigest()==ARCHIVE_HASH,'repository-archive-manifest')
 return json.loads(path.read_text())
def raw_path(p):
 path=Path(p)
 if path.is_file():return path
 if path.parent==RAW:
  matches=[r for r in archive_manifest()['rows'] if r['originalPath']==str(path)]
  require(len(matches)==1,'repository-fallback-identity');row=matches[0];fallback=HERE/row['archivePath']
  require(fallback.is_file() and fallback.stat().st_size==row['bytes'] and hashlib.sha256(fallback.read_bytes()).hexdigest()==row['sha256'],'repository-fallback-bytes')
  return fallback
 return path
def sha(p):return hashlib.sha256(raw_path(p).read_bytes()).hexdigest()
def verify_archive():
 manifest=archive_manifest();names=[]
 for row in manifest['rows']:
  relative=Path(row['archivePath'])
  require(relative.parts[0]=='raw-arm64-v2' and len(relative.parts)==2 and relative.name not in names,'repository-archive-shape');names.append(relative.name)
  path=HERE/relative
  require(path.is_file() and path.stat().st_size==row['bytes'] and hashlib.sha256(path.read_bytes()).hexdigest()==row['sha256'],'repository-archive-bytes')
 require(len(names)==13 and {p.name for p in (HERE/'raw-arm64-v2').iterdir()}==set(names),'repository-archive-coverage')
 require(manifest['totalBytes']==sum(row['bytes'] for row in manifest['rows']),'repository-archive-size')
def require(ok,reason):
 if not ok:raise ValueError(reason)
def source(m):return SDK/f'System/Library/Frameworks/{m}.framework/Versions/A/Modules/{m}.swiftmodule/arm64e-apple-macos.swiftinterface'
def expected_argv(m):
 header=shlex.split(source(m).read_text().splitlines()[2].split(': ',1)[1]);flags=[];i=0
 while i<len(header):
  if header[i] in {'-target','-target-variant','-target-arch-variant'}:
   if header[i]=='-target':flags+=['-target',TARGET]
   i+=2
  else:flags.append(header[i]);i+=1
 return [str(TOOL),'-dump-ast','-parse-as-library','-sdk',str(SDK)]+flags+[str(source(m))]
def verify_receipt(m,r):
 require(r['argv']==expected_argv(m),'target-header-argv')
 require(r['cwd']==str(RAW),'capture-cwd')
 require(type(r['exitCode']) is int and r['exitCode']==0 and r['timedOut'] is False,'successful-semantic-ast')
 require(r['tool']['path']==str(TOOL) and r['tool']['sha256']=='sha256:'+sha(TOOL),'live-compiler')
 require(r['inputs']==[{'path':str(source(m)),'sha256':'sha256:'+sha(source(m)),'bytes':source(m).stat().st_size}],'live-source')
 for channel in ['stdout','stderr']:
  f=RAW/(m+'-arm64.'+channel);d=r[channel]
  require(d=={'path':str(f),'sha256':'sha256:'+sha(f),'bytes':raw_path(f).stat().st_size},'raw-ast-'+channel)
def header_projection(raw):
 kind=re.match(r'\s*\((class_decl|struct_decl|enum_decl|extension_decl|destructor_decl)\b',raw)
 if not kind:return None
 loc=re.search(r'range=\[(.*?):(\d+):(\d+) - line:(\d+):(\d+)\]',raw)
 if not loc:return None
 name=re.match(r'\s*"([^"]+)"',raw[loc.end():]);access=re.search(r'\baccess=(\w+)',raw)
 return {'kind':kind[1],'source':loc[1],'line':int(loc[2]),'column':int(loc[3]),'endLine':int(loc[4]),'endColumn':int(loc[5]),'name':name[1] if name else None,'access':access[1] if access else None,'raw':raw,'indent':len(raw)-len(raw.lstrip())}
def parse_ast(text,m):
 stack=[];result=[]
 for raw in text.splitlines():
  indent=len(raw)-len(raw.lstrip())
  while stack and stack[-1]['indent']>=indent:stack.pop()
  node=header_projection(raw)
  if node is None:continue
  if node['kind']=='destructor_decl':node['owners']=[dict(n) for n in stack];result.append(node)
  else:stack.append(node)
 return result

def demangle_rows(text):
 result={}
 for block in re.split(r'^Demangling for ',text,flags=re.M)[1:]:
  usr,body=block.split('\n',1);require(usr.startswith('$s'),'demangle-usr-form');normalized='s:'+usr[2:];require(normalized not in result,'duplicate-demangle')
  roots=[];stack=[];summary=[]
  for line in body.splitlines():
   if not line:continue
   match=re.fullmatch(r'( *)(?:kind=)([A-Za-z]+)(?:, text=("(?:[^"\\]|\\.)*"))?',line)
   if not match:summary.append(line);continue
   require(not summary,'demangle-tree-after-result');depth=len(match[1]);require(depth%2==0,'demangle-depth')
   node={'kind':match[2],'text':json.loads(match[3]) if match[3] else None,'children':[]}
   while stack and stack[-1][0]>=depth:stack.pop()
   if not stack:require(depth==0,'demangle-root-depth');roots.append(node)
   else:require(depth==stack[-1][0]+2,'demangle-depth');stack[-1][1]['children'].append(node)
   stack.append((depth,node))
  require(len(roots)==1 and roots[0]['kind']=='Global' and roots[0]['text'] is None and len(roots[0]['children'])==1,'demangle-global')
  destructor=roots[0]['children'][0]
  require(destructor['kind']=='Destructor' and destructor['text'] is None and len(destructor['children'])==1,'demangle-destructor-kind')
  def leaf(n,kind):
   require(n['kind']==kind and isinstance(n['text'],str) and bool(n['text']) and not n['children'],'demangle-leaf');return n['text']
  def nominal(n):
   require(n['kind'] in {'Class','Structure','Enum'} and n['text'] is None and len(n['children'])==2,'demangle-nominal-kind')
   context,identifier=n['children'];name=leaf(identifier,'Identifier');extension=None
   if context['kind']=='Module':
    module=leaf(context,'Module');owners=[];render=module
   elif context['kind']=='Extension':
    require(context['text'] is None and len(context['children'])==2,'demangle-extension')
    extension=leaf(context['children'][0],'Module');module,owners,render,_=nominal(context['children'][1]);render='(extension in '+extension+'):'+render
   else:module,owners,render,extension=nominal(context)
   return module,owners+[{'name':name,'kind':n['kind']}],render+'.'+name,extension
  require(destructor['children'][0]['kind']=='Class','demangle-destructor-class')
  module,owners,render,extension=nominal(destructor['children'][0])
  require(summary==[render+'.deinit'],'demangle-result')
  result[normalized]={'identifiers':[n['name'] for n in owners],'ownerKinds':[n['kind'] for n in owners],'nominalModule':module,'extensionModule':extension,'modules':[module] if extension is None else [extension,module],'tree':roots[0],'raw':body}
 return result

def raw_indices():
 import importlib.util
 root=HERE.parents[3];link=root/'factory/catalogue/compiler-cursor-spike/link-evidence.json';helper=root/'factory/catalogue/module-provenance-spike/exact_validator.py'
 require(sha(link)=='836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec','index-link-pin')
 require(sha(helper)=='83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5','index-parser-pin')
 spec=importlib.util.spec_from_file_location('frozen_raw_index_parser',helper);h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
 records={}
 for interface in json.loads(link.read_text())['interfaces']:
  path=root/interface['indexOutput'];require('sha256:'+sha(path)==interface['indexOutputSha256'],'index-output-pin')
  request=root/interface['indexRequest'];require('sha256:'+sha(request)==interface['indexRequestSha256'],'index-request-pin')
  require(interface['requestIdentity']['target']==TARGET and interface['requestIdentity']['moduleName']==interface['module'] and interface['requestIdentity']['sourcefile']==str(source(interface['module'])),'index-request-identity')
  records[interface['module']]=h.entities(path.read_text())
 return records

def source_conditions(lines,line):
 stack=[]
 for number,text in enumerate(lines[:line-1],1):
  directive=re.match(r'\s*#(if|elseif|else|endif)\b',text)
  if not directive:continue
  kind=directive[1]
  if kind=='if':stack.append({'ifLine':number,'branchLine':number,'kind':'if'})
  elif kind=='endif':
   require(bool(stack),'conditional-balance');stack.pop()
  else:
   require(bool(stack),'conditional-balance');stack[-1]={'ifLine':stack[-1]['ifLine'],'branchLine':number,'kind':kind}
 return stack

def evaluate(row,nodes,demangles,index_records):
 m=row['module'];src=source(m);fields=row['cursor']['fields'];line=row['line']
 require(fields['kind']=='source.lang.swift.decl.function.destructor' and fields['name']=='deinit' and fields['modulename']==m and fields['line']==line,'cursor-destructor-identity')
 require(Path(fields['filepath']).resolve()==src.resolve() and row['source']['sha256']=='sha256:'+sha(src),'cursor-source-identity')
 lines=src.read_text().splitlines(keepends=True);text=lines[line-1].rstrip('\r\n')
 require(row['sourceLine']==text and 'deinit' in text,'source-line')
 require(row['conditions']==source_conditions(lines,line),'source-conditions')
 offset=sum(len(x.encode()) for x in lines[:line-1])+len(text[:text.index('deinit')].encode())
 require(row['deinitByteOffset']==fields['offset']==offset,'source-offset')
 matches=[n for n in nodes if n['line']==line and n['source']==str(src)]
 require(len(matches)==1,'ast-node-cardinality');node=matches[0]
 require(node['kind']=='destructor_decl' and node['name']=='deinit' and node['access'] in {'public','open','internal','package','private','fileprivate'},'ast-destructor-access')
 require(header_projection(node['raw'])=={k:v for k,v in node.items() if k!='owners'},'ast-derived-node')
 require('<error' not in node['raw'] and 'interface_type=' in node['raw'],'typed-destructor')
 require(node['column']==fields['column']==len(text[:text.index('deinit')])+1 and node['endLine']==line and node['endColumn']==node['column'],'ast-source-position')
 owners=node['owners'];require([n['line'] for n in owners]==row['scopeLines'] and bool(owners),'ast-owner-range')
 require(all(n['source']==str(src) and n['line']<=line<=n['endLine'] for n in owners),'ast-owner-source-range')
 d=demangles.get(fields['usr']);require(d is not None and (d['extensionModule'] or d['nominalModule'])==m,'demangle-module')
 require(d['nominalModule']==('__C' if (m,line)==('SwiftUI',32548) else m) and (d['extensionModule'] is None or owners[0]['kind']=='extension_decl'),'demangle-nominal-module')
 require(d==demangle_rows('Demangling for $s'+fields['usr'][2:]+'\n'+d['raw'])[fields['usr']],'demangle-derived-tree')
 require([n['name'] for n in owners]==d['identifiers'],'demangle-owner-chain')
 raw=[e for e in index_records if e.get('usr')==fields['usr'] and e.get('line')==line and e.get('name')=='deinit']
 require(len(raw)==1,'raw-member-cardinality');entity=raw[0]
 require(entity['kind']=='source.lang.swift.decl.function.destructor' and entity['column']==fields['column'],'raw-member-kind-position')
 context=entity['sourcekitContext'];require(len(context)==len(owners),'raw-owner-cardinality')
 kinds={'class_decl':'class','struct_decl':'struct','enum_decl':'enum'};nominals={'Class':'class','Structure':'struct','Enum':'enum'}
 for index,(owner,raw_owner,nominal_kind) in enumerate(zip(owners,context,d['ownerKinds'])):
  require(owner['name']==raw_owner['name'] and owner['line']==raw_owner['line'],'raw-owner-identity')
  expected='source.lang.swift.decl.'+('extension.' if owner['kind']=='extension_decl' else '')+nominals[nominal_kind]
  require(raw_owner['kind']==expected and (owner['kind']=='extension_decl' or kinds.get(owner['kind'])==nominals[nominal_kind]),'raw-owner-kind')
 require(context[-1]['usr']==fields['usr'][:-2],'raw-owner-usr')

 require(all(header_projection(n['raw'])==n for n in owners),'ast-derived-owner')
 require(all(n['kind']=='extension_decl' or n['access'] in {'public','open','internal','package','private','fileprivate'} for n in owners),'typed-owner-access')
 return {'module':m,'line':line,'usr':fields['usr'],'usrIdentityScope':'frozen836 textual SourceKit index/cursor lineage; AST emits no declaration USR & canonical ABI namespace is not asserted','source':row['source'],'deinitByteOffset':offset,'conditions':row['conditions'],'target':TARGET,'targetVariant':None,'effectiveAccess':node['access'],'astNode':node,'demangle':d,'rawIndexEntity':entity,'cursorResponse':row['response'],'sourceKitRequest':row['request'],'interpretation':'compiler-reported-member-access; enclosing-owner eligibility remains separate'}
def verify_all():
 verify_archive()
 require(sha(SEED)==SEED_HASH,'seed-pin');seed=json.loads(SEED.read_text());require(len(seed['rows'])==42,'bounded-42')
 require(sha(HERE/'raw-pins.json')==RAW_PINS_HASH,'raw-pin-manifest')
 pins=json.loads((HERE/'raw-pins.json').read_text())
 for p in pins:
  require(sha(p['path'])==p['sha256'],'raw-tool-request-pin')
 for row in seed['rows']:
  for key in ['response','request']:
   desc=row[key];f=HERE.parents[3]/desc['path'];require('sha256:'+sha(f)==desc['sha256'],'sourcekit-raw-pin')
 demangles=demangle_rows(raw_path(RAW/'demangle.stdout').read_text())
 require(set(demangles)=={r['cursor']['fields']['usr'] for r in seed['rows']},'exact-demangle-set')
 records={}
 for m in ['SwiftUI','SwiftUICore']:
  r=json.loads(raw_path(RAW/(m+'-arm64.receipt.json')).read_text());verify_receipt(m,r);records[m]=parse_ast(raw_path(RAW/(m+'-arm64.stdout')).read_text(),m)
 indices=raw_indices()
 rows=[evaluate(row,records[row['module']],demangles,indices[row['module']]) for row in seed['rows']]
 return {'kind':'bounded-destructor-compiler-effective-access-proof','status':'independent-review-pending','sourceKitSeedHash':'sha256:'+SEED_HASH,'target':TARGET,'rows':rows,'summary':dict(Counter(r['effectiveAccess'] for r in rows)),'promotionsMade':0,'rule':'Explicit compiler effective access settles physical SDK declaration access only; frozen textual SourceKit USRs are lineage, not proof of canonical ABI IDs; owner access/API-addressability decisions remain separate.'}
if __name__=='__main__':
 out=verify_all();(HERE/'effective-access-evidence.json').write_text(json.dumps(out,indent=2)+'\n');print(out['summary'])
