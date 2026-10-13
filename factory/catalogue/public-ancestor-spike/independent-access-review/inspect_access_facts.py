#!/usr/bin/env python3
"""Read-only attributed public identity facts from immutable source/index bytes."""
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
LINK=ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json'
HELPER=ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py'
LINK_PIN='836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec'
HELPER_PIN='83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5'
def sha(data):return hashlib.sha256(data).hexdigest()
def module():
 assert sha(HELPER.read_bytes())==HELPER_PIN
 spec=importlib.util.spec_from_file_location('pinned_access_raw_helper',HELPER)
 result=importlib.util.module_from_spec(spec);spec.loader.exec_module(result);return result

def main():
 assert sha(LINK.read_bytes())==LINK_PIN
 helper=module();link=json.loads(LINK.read_text());findings=[];inputs={};no_spi={};nominal_defaults={}
 targets={'SwiftUI':{239:'SnapshotResponse',240:'init(restoredDefaultState:estimatedSnapshotExpiration:identifier:)'},'SwiftUICore':{6136:'DepthAlignmentKey',6137:'<(_:_:)',6151:'depthKey',12412:'AnyLocationBase',12420:'AnyLocation',14128:'key',14146:'key',15540:'init(wrappedValue:)',15542:'init(projectedValue:)',15556:'init(wrappedValue:)'}}
 for interface in link['interfaces']:
  name=interface['module'];source=Path(interface['path']);index=ROOT/interface['indexOutput'];source_bytes=source.read_bytes();index_bytes=index.read_bytes()
  assert 'sha256:'+sha(source_bytes)==interface['sha256'];assert 'sha256:'+sha(index_bytes)==interface['indexOutputSha256']
  inputs[name]={'source':{'path':str(source),'sha256':sha(source_bytes)},'index':{'path':str(index),'sha256':sha(index_bytes)}}
  text=source_bytes.decode();lines=text.splitlines();model=helper.source_model(text);entities=helper.entities(index_bytes.decode())
  no_spi[name]='@_spi' not in text;assert no_spi[name]
  nominal_defaults[name]=[]
  def attrs(number):
   original=lines[number-1];result=[{'line':number,'text':original}]
   cursor=number-1
   while cursor>0 and lines[cursor-1].strip().startswith('@'):
    if model[cursor]['scopes']!=model[number]['scopes'] or model[cursor]['conditions']!=model[number]['conditions']:break
    result.insert(0,{'line':cursor,'text':lines[cursor-1]});cursor-=1
   return result
  for e in entities:
   if e.get('is_implicit'):continue
   if e['kind'] in ('source.lang.swift.decl.struct','source.lang.swift.decl.class','source.lang.swift.decl.enum','source.lang.swift.decl.protocol') and e.get('effective_access')=='source.decl.effective_access.public':
    if not __import__('re').search(r'\b(public|open)\b',lines[e['line']-1]):nominal_defaults[name].append(e)
  for line,wanted in targets[name].items():
   candidates=[e for e in entities if e['line']==line and e['name']==wanted and not e.get('is_implicit')]
   assert len(candidates)==1 and candidates[0]['effective_access']=='source.decl.effective_access.public'
   entity=candidates[0]
   chain=[{'line':c['line'],'name':c['name'],'kind':c['kind'],'sourceAttributes':attrs(c['line'])} for c in entity['sourcekitContext']]
   findings.append({'module':name,'line':line,'name':wanted,'usr':entity['usr'],'rawEffectiveAccess':entity['effective_access'],'ownSourceAttributes':attrs(line),'physicalOwnerSourceAttributes':chain,'sourceConditions':model[line]['conditions']})
 assert not any(nominal_defaults.values())
 result={'kind':'independent-access-attribution-facts','scope':'exact immutable836 two arm64e interface source/index streams','inputs':inputs,'linkSha256':LINK_PIN,'helperSha256':HELPER_PIN,'reviewerSourceSha256':sha(Path(__file__).read_bytes()),'noSpiInPinnedPublicSources':no_spi,'publicNominalsWithoutOwnPublicOrOpenModifier':nominal_defaults,'findings':findings,'reviewRules':['Documentation visibility private proves documentation suppression; raw compiler still reports public access.','Target macOS unavailable or wildcard unavailable must inherit from own attributes, physical extensions & resolved nominal ancestors.','Other-platform unavailability does not prove macOS compiler ineligibility.','Missing raw identities, unresolved external owners & ambiguous owners remain held without direct hidden proof.'],'promotionsMade':0}
 output=HERE/'attributed-public-facts.json';encoded=json.dumps(result,sort_keys=True,indent=2)+'\n';output.write_text(encoded)
 print('12 attributed public facts verified; no SPI; 0 default-access public nominals; promotions 0')
if __name__=='__main__':main()
