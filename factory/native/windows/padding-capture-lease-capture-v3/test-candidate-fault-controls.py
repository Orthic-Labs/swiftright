"""Offline production-validator mutation controls; rejected fixtures invoke no action."""
from __future__ import annotations
import copy, importlib.util, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('adapter',HERE.parent/'settled-capture-adapter-v3'/'adapter.py')
adapter=importlib.util.module_from_spec(spec);spec.loader.exec_module(adapter)

def fixture():
 plan={'case':{'id':'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258','hash':'sha256:'+'a'*64},'runtimeSourceCommit':'37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b','rendererSha256':'b'*64}
 compile_record={'exeSha256':'c'*64}
 refs={f'raw{i}':{'path':f'factory/oracle/mac/context-{i}.json','sha256':'sha256:'+('%064x'%i),'bytes':i+1} for i in range(3)}
 t={'id':'sr1-source-bound-r11-20261011','sdk':'/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk','macosBuild':'26A434','toolchains':{'macSwift':'actual swiftc envelope','winSwift':'Swift 6.4'},'runtimeCommit':plan['runtimeSourceCommit'],'rendererHash':'sha256:'+plan['rendererSha256'],'hostHashes':{'macos':adapter.MAC_FRESH20_BINARY_HASH,'windows':'sha256:'+compile_record['exeSha256']},'factoryVersion':'0.1-working-observation','acceptanceConfigHash':adapter.MAC_FRESH20_ACCEPTANCE_HASH}
 tup={'kind':'factory-source-bound-candidate-canonical-tuple-v1','version':1,'candidateID':t['id'],'case':copy.deepcopy(plan['case']),'frozenTupleBound':False,'tuple':t,'sourceInputs':refs,'_rawSha256':'sha256:'+'d'*64}
 candidate={'kind':'factory-source-bound-candidate-binding-v1','version':1,'canonicalTupleRef':{'path':'candidate-tuple.json','sha256':tup['_rawSha256'],'bytes':100},'canonicalInputs':refs['raw0'],'sourceBinding':refs['raw1'],'frozenTupleBound':False,'runtime':{'sourceCommit':plan['runtimeSourceCommit'],'sourceTreeHash':'sha256:'+'e'*64},'renderer':{'sha256':'sha256:'+plan['rendererSha256']}}
 metadata={'kind':'factory-prelaunch-capture-metadata-v2','version':2,'expectedCount':1,'frozenTupleBound':False,'historicalTemplateTupleClosed':False,'candidateTuple':{'sha256':tup['_rawSha256']},'sourceBoundCandidateTuple':{'sha256':'sha256:'+'f'*64}}
 phase={'phase':'close-pending','nativeActions':0}
 return tup,candidate,plan,compile_record,metadata,phase

def reject(name,mutate):
 tup,candidate,plan,compile_record,metadata,phase=fixture();mutate(tup,candidate,plan,compile_record,metadata,phase);calls=[]
 try: adapter.validate_candidate_wrapper(tup,candidate,plan,compile_record,metadata,phase,lambda:calls.append('action'))
 except (ValueError,KeyError,TypeError):
  assert calls==[],f'{name}: action reached'
  return {'control':name,'passed':True,'spyActions':len(calls)}
 raise AssertionError(name+': mutation accepted')

# Actual tuple/candidate production validator mutations.
rows=[]
rows.append(reject('wrong-tuple-kind',lambda t,c,p,x,m,q:t.__setitem__('kind','wrong')))
rows.append(reject('wrong-case',lambda t,c,p,x,m,q:t['case'].__setitem__('id','wrong.case')))
rows.append(reject('wrong-runtime',lambda t,c,p,x,m,q:t['tuple'].__setitem__('runtimeCommit','0'*40)))
rows.append(reject('wrong-renderer',lambda t,c,p,x,m,q:t['tuple'].__setitem__('rendererHash','sha256:'+'f'*64)))
rows.append(reject('wrong-metadata',lambda t,c,p,x,m,q:m.__setitem__('frozenTupleBound',True)))
rows.append(reject('wrong-phase',lambda t,c,p,x,m,q:q.__setitem__('phase','pixels-start')))
print(json.dumps({'kind':'factory-candidate-fault-controls-v2','status':'passed','controls':rows,'nativeActions':0,'compilerActions':0,'guiActions':0,'remoteActions':0,'lockActions':0},separators=(',',':')))
