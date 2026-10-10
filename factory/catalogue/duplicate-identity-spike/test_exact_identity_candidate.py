#!/usr/bin/env python3
"""Build deterministic review-only candidate & execute targeted semantic faults."""
import copy
import json
from pathlib import Path
import exact_identity_candidate as guard

HERE=guard.HERE

def baseline_args(source_row, payload):
 source=source_row['source']; spec=guard.frozen()['rows'][source_row['line']]; link=spec['link']
 return {'row':{'module':source_row['module'],'sourceHash':source['sha256'],'line':source_row['line'],'kind':source_row['kind'],'name':source_row['name'],'context':source_row['context'],'sourceLine':source['lineText'],'activeCondition':source['expectedCondition'],'activeBranch':source['activeBranch']['active'],'scopeName':source['enclosingScope']['name'],'scopeLine':source['enclosingScope']['line'],'auditRowKey':link['auditRowKey'],'signature':link['signature'],'key':source_row['key']},
 'raw_entities':source_row['raw']['parsedEntities'],'raw_records':source_row['raw']['records'],
 'source_text':guard.SOURCE.read_text(),'source_sha256':source['sha256'],
 'request_text':guard.REQUEST.read_text(),'request_sha256':payload['inputs']['request']['sha256'],'expected_request_sha256':payload['inputs']['request']['sha256'],
 'response_sha256':payload['receipts']['sourcekit']['stdout']['sha256'],'expected_response_sha256':payload['inputs']['frozenResponse']['sha256'],
 'raw_response_text':(HERE/'sourcekit-index-output.txt').read_text(),
 'demangle_text':(HERE/'exact-demangle.stdout').read_text(),'toolchain':payload['toolchain'],'expected_toolchain':copy.deepcopy(payload['toolchain']),'source_path':str(guard.SOURCE)}

def build():
 payload=json.loads((HERE/'raw-record-evidence.json').read_text()); rows=[]
 for source_row in payload['rows']:
  args=baseline_args(source_row,payload); accepted=guard.validate_duplicate_identity(**args); assert accepted['accepted'],accepted
  controls={}
  def reject(label, changed, reason):
   outcome=guard.validate_duplicate_identity(**changed)
   assert not outcome['accepted'] and reason in outcome['reasons'],(label,outcome)
   controls[label]={'rejected':True,'requiredReason':reason,'reasons':outcome['reasons']}
  # Equal paired cards reach specific semantic identity gates. Neither distinct-pair
  # nor cardinality gates can account for these failures.
  faults={'usr': 's:7SwiftUI999WrongUSR','kind':'source.lang.swift.decl.class','effective_access':'source.decl.effective_access.internal','name':'wrongName','line':source_row['line']+1,'column':15,'sourcekitContext':[{'kind':'source.lang.swift.decl.struct','name':'WrongOwner','usr':'s:7SwiftUI10WrongOwnerV'}],'is_implicit':True}
  for field,value in faults.items():
   changed=copy.deepcopy(args)
   for entity in changed['raw_entities']:entity[field]=value
   assert changed['raw_entities'][0]==changed['raw_entities'][1]
   reject('both-identical-'+field,changed,'semantic-'+field)
   assert 'distinct-entities' not in controls['both-identical-'+field]['reasons']
  # Both full blocks identically changed & rehashed, with matching complete response:
  # reparse binds evidence successfully, but frozen source identity rejects wrong USR.
  changed=copy.deepcopy(args); block=changed['raw_records'][0]['text']; bad=block.replace(changed['raw_entities'][0]['usr'],'s:7SwiftUI999WrongUSR')
  changed['raw_response_text']=changed['raw_response_text'].replace(block,bad)
  parsed=[r for r in guard.reconstruct_response(changed['raw_response_text']) if r['entity'].get('line')==source_row['line'] and r['entity'].get('name')==source_row['name']]
  changed['raw_records']=[r['record'] for r in parsed];changed['raw_entities']=[r['entity'] for r in parsed]
  changed['response_sha256']=changed['expected_response_sha256']=guard.digest_bytes(changed['raw_response_text'].encode())
  assert len(parsed)==2 and changed['raw_records'][0]==changed['raw_records'][1] and changed['raw_entities'][0]==changed['raw_entities'][1]
  reject('both-full-blocks-and-response-rehashed-wrong-usr',changed,'semantic-usr')
  assert 'records-response-binding' not in controls['both-full-blocks-and-response-rehashed-wrong-usr']['reasons']
  def variant(**updates):
   changed=copy.deepcopy(args);changed.update(updates);return changed
  changed=variant(); changed['raw_entities'][1]['column']=15;reject('true-distinct-card',changed,'distinct-entities')
  reject('third-card',variant(raw_entities=args['raw_entities']+[copy.deepcopy(args['raw_entities'][0])]),'cardinality')
  changed=variant();changed['raw_records'][1]['text']+='\n';changed['raw_records'][1]['sha256']=guard.digest_bytes(changed['raw_records'][1]['text'].encode());reject('distinct-full-block',changed,'distinct-records')
  reject('changed-full-response',variant(raw_response_text=args['raw_response_text']+'\n'),'response-bytes')
  reject('extra-request-build-flag',variant(request_text=args['request_text'].replace(' ]',', "-D", "WRONG_BUILD" ]')),'request-bytes')
  text=args['request_text']+'\n'; reject('coforged-request-pins',variant(request_text=text,request_sha256=guard.digest_bytes(text.encode()),expected_request_sha256=guard.digest_bytes(text.encode())),'request-bytes')
  changed=variant();changed['row']['scopeName']='SnapshotResponse';changed['row']['scopeLine']=239;reject('real-wrong-sdk-scope',changed,'source-scope')
  changed=variant();changed['row']['activeBranch']=False;reject('branch-flag',changed,'source-branch')
  lines=args['source_text'].splitlines(keepends=True); start=source_row['source']['enclosingScope']['line']; idx=next(i for i in range(source_row['line']-1,-1,-1) if lines[i].strip()=='#if '+guard.CONDITION);lines[idx]=lines[idx].replace('>=5.3','>=99.0');reject('actual-condition-mutated',variant(source_text=''.join(lines)),'source-lexical')
  changed=variant();changed['row']['signature']+=' ';reject('frozen-signature',changed,'frozen-row-signature-key')
  changed=variant();changed['row']['line']=4101;reject('nonallowlisted-sdk-row',changed,'exact-five-key')
  changed=variant();changed['toolchain']['target']='x86_64-apple-macosx27.0';changed['expected_toolchain']=copy.deepcopy(changed['toolchain']);reject('coforged-toolchain',changed,'toolchain-identity')
  marker='Demangling for $s'+args['raw_entities'][0]['usr'][2:]; begin=args['demangle_text'].index(marker);end=args['demangle_text'].find('\nDemangling for ',begin+1); section=args['demangle_text'][begin:end if end>=0 else len(args['demangle_text'])]
  reject('duplicate-demangle-section',variant(demangle_text=args['demangle_text']+'\n'+section),'usr-full-tree')
  reject('full-owner-tree-mutated',variant(demangle_text=args['demangle_text'][:begin]+section.replace('kind=Structure','kind=Class',1)+args['demangle_text'][end if end>=0 else len(args['demangle_text']):]),'usr-full-tree')
  reject('extra-nominal-tree-child',variant(demangle_text=args['demangle_text'][:begin]+section.replace('      kind=Module, text="SwiftUI"','      kind=Module, text="SwiftUI"\n      kind=Identifier, text="ForgedOwner"',1)+args['demangle_text'][end if end>=0 else len(args['demangle_text']):]),'usr-full-tree')
  # Context independently parsed from actual raw ancestors must exactly equal SDK owner.
  lex=guard.frozen()['rows'][source_row['line']]['lexical']; positions=[{k:r[k] for k in ('startByte','endByte')} for r in guard.frozen()['rows'][source_row['line']]['pair']]
  rows.append({'key':source_row['key'],'auditRowKey':args['row']['auditRowKey'],'signature':args['row']['signature'],'usr':args['raw_entities'][0]['usr'],'validator':accepted,'sourceReconstruction':lex,'rawPositions':positions,'faultControls':controls,'decision':{'status':'held','promotion':None}})
 inputs={key:{'path':str(path),'sha256':guard.file_digest(path)} for key,path in [('link',guard.LINK),('source',guard.SOURCE),('request',guard.REQUEST),('response',guard.FROZEN),('freshResponse',HERE/'sourcekit-index-output.txt'),('legacyRawEvidence',HERE/'raw-record-evidence.json'),('validator',HERE/'exact_identity_candidate.py'),('test',HERE/'test_exact_identity_candidate.py'),('probeCapture',HERE/'capture_exact_probes.py'),('freshProbeReceipts',HERE/'exact-probe-receipts.json'),('branchProbe',HERE/'tilde-sendable-probe.swift'),('freshBranchOutput',HERE/'exact-branch.stdout'),('freshDemangleOutput',HERE/'exact-demangle.stdout')]}
 return {'kind':'duplicate-exact-identity-review-candidate','version':2,'status':'review-only','inputs':inputs,'toolchain':guard.frozen()['toolchain'],'pins':guard.PINS,'rows':rows,'summary':{'acceptedDuplicatePairs':5,'faultControls':sum(len(r['faultControls']) for r in rows),'promotionsMade':0}}

def main():
 first=json.dumps(build(),indent=2,sort_keys=True)+'\n';second=json.dumps(build(),indent=2,sort_keys=True)+'\n';assert first==second,'whole artifact replay mismatch'
 (HERE/'exact-identity-candidate.json').write_text(first)
 print('5 exact pairs accepted; '+str(json.loads(first)['summary']['faultControls'])+' targeted faults rejected; whole artifact replay byte-equal; promotions 0')
if __name__=='__main__':main()
