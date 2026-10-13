#!/usr/bin/env python3
"""Control-only completion probe for all WindowsExitProof archive joins.

It derives observation identity/HWND from preserved old-r3 owned/close bytes,
uses exact fetched compiler bytes, & resolves host/runtime/raw archives by
pinned refs. It never writes admission artifacts or performs native actions.
Fault fixtures exercise PID, HWND, terminal certificate, & sealed raw closure.
"""
from __future__ import annotations
import argparse, copy, hashlib, importlib, json, re, sys
from pathlib import Path
ROLES=('outcome','observation','owned','close','plan','compile','witness','exe','renderer','runtimeReceipt','runtimeTree','stdout','stderr')

def dig(b): return 'sha256:'+hashlib.sha256(b).hexdigest()
def readj(p): return json.loads(Path(p).read_bytes().decode('utf-8-sig'))
def canon(o): return json.dumps(o,ensure_ascii=False,indent=2,sort_keys=True).encode()+b'\n'
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--repo',type=Path,default=Path('.')); ap.add_argument('--output',type=Path,required=True); a=ap.parse_args(); repo=a.repo.resolve(strict=True)
 base=repo/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1'; m=readj(base/'count1-input-map-r6.actual.json'); run=m['runs'][0]; roles=m['roles']; src=m['source']
 native=repo/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1/observed-native-r3/actual-single-r1/native-01'
 old={
  'outcome':repo/run['outcome'],'owned':repo/run['owned'],'close':repo/run['close'],'plan':repo/roles['plan'],'compile':repo/roles['compile'],'witness':repo/src['Sources/FactoryProbe/Witness.swift'],'exe':repo/roles['exe'],'renderer':repo/roles['renderer'],'runtimeReceipt':repo/src['runtime-source-receipt.json'],'runtimeTree':repo/src['runtime-source-tree.json'],'stdout':native/'host.stdout.txt','stderr':native/'host.stderr.txt'}
 raw={k:p.read_bytes() for k,p in old.items()}; parsed={k:readj(p) for k,p in old.items() if k not in ('witness','exe','renderer','stdout','stderr')}
 # Explicit control fixture derived only from preserved identity/close fields.
 obs=readj(repo/run['observation']); owned=parsed['owned']; close=parsed['close']; obs['ownedIdentity']=copy.deepcopy(owned); obs['hwnd']=close['hwnd']; obs['_controlOnlyFixture']={'derivedFrom':['owned-process.json','owned-close.json'],'productionAdmission':False}
 out_fixture=copy.deepcopy(parsed['outcome']); out_fixture['rawHashStates']={name:{'sha256':out_fixture[name+'Sha256'],'qualification':'sealed-raw','error':''} for name in ('stdout','stderr')}; raw['outcome']=canon(out_fixture); parsed['outcome']=out_fixture
 for f in obs['files']:
  if f['path']=='capture-outcome.json': f['sha256']=hashlib.sha256(raw['outcome']).hexdigest(); f['bytes']=len(raw['outcome'])
 raw['observation']=canon(obs)
 plan=parsed['plan']; compile_record=parsed['compile']; tree=parsed['runtimeTree'];
 compiler_meta=readj(repo/'factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/compiler-byte-archive-r1.json'); compiler_path=Path(compiler_meta['physicalPath']); compiler=compiler_path.read_bytes(); assert dig(compiler)==('sha256:'+compiler_meta['sourceRef']['sha256']) and len(compiler)==compiler_meta['sourceRef']['bytes']
 proof_paths={'outcome':'capture-outcome.json','owned':'owned-process.json','close':'owned-close.json','stdout':'host.stdout.txt','stderr':'host.stderr.txt'}
 proof={'version':1,'files':{r:{'path':proof_paths.get(r,f'control-only/r2/roles/{r}.raw'),'hash':dig(raw[r])} for r in ROLES}}
 exe=dig(raw['exe']); renderer=dig(raw['renderer']); witness=dig(raw['witness']);
 capture={'controlOnly':True,'controlOnlyID':'control-only/windows-exit-proof-r2-complete','platform':'windows','case':plan['case'],'tuple':{'rendererHash':renderer,'runtimeCommit':plan['runtimeSourceCommit']},'provenance':{'sourceHash':witness},'meta':{'controlOnly':True,'captureID':'control-only/capture/r2','imageID':'control-only/image/r2','run':1,'host':{'hash':exe},'clock':{'correlationHash':dig(raw['observation'])},'conditions':{'windowsExitProof':proof,'actualSourceHash':witness,'actualHostExecutableHash':exe,'actualRendererHash':renderer,'rawReceiptHash':dig(raw['observation'])}}}
 sys.path.insert(0,str(repo)); gate=importlib.import_module('factory.gate.windows_exit_admission')
 runtime_root=repo/'factory/native/windows/module-origin-37429120-20261011/runtime'; source_refs={k:repo/v for k,v in src.items() if k in plan.get('sourceBindings',[]) and isinstance(v,str)}
 # source map by semantic path, preserving exact bytes from pinned source refs
 host={b['path']:repo/src.get(b['path'], '') for b in plan['sourceBindings']}
 runtime={x['path']:(runtime_root/x['path'],x['sha256']) for x in tree}
 rawfiles={x['path']:native/x['path'] for x in obs['files']}
 rawfiles['compile.stdout.bin']=repo/'factory/native/windows/padding-capture-lease-build-v1/actual-build-r1/compile.stdout.bin'; rawfiles['compile.stderr.bin']=repo/'factory/native/windows/padding-capture-lease-build-v1/actual-build-r1/compile.stderr.bin'
 def run_gate(c, raw_override=None, fault='positive'):
  use=dict(raw); use.update(raw_override or {}); counts={r:0 for r in ROLES}; reads=[]
  c=copy.deepcopy(c); c['meta']['conditions']['rawReceiptHash']=c['meta']['clock']['correlationHash']=dig(use['observation'])
  c['meta']['conditions']['windowsExitProof']={'version':1,'files':{r:{'path':proof_paths.get(r,f'control-only/r2/roles/{r}.raw'),'hash':dig(use[r])} for r in ROLES}}
  def reader(path):
   if path.startswith('control-only/r2/roles/') and path.endswith('.raw'):
    role=path[len('control-only/r2/roles/'):-4]; counts[role]+=1; return use[role]
   for role,semantic in proof_paths.items():
    if path == semantic:
     counts[role]+=1; return use[role]
   if path=='tool/compiler.bin': reads.append(path); return compiler
   if path.startswith('host/'):
    p=host.get(path[5:]);
    if p and p.exists(): reads.append(path); return p.read_bytes()
   if path.startswith('runtime/'):
    entry=runtime.get(path[8:]); p=entry[0] if entry else None
    if p and p.exists(): reads.append(path); return p.read_bytes()
   p=rawfiles.get(path)
   if p and p.exists(): reads.append(path); return p.read_bytes()
   raise FileNotFoundError(path)
  result=gate.verify_windows_exit_admission(c,read_bytes=reader)
  return {'name':fault,'status':result['status'],'issues':result['issues'],'proofRoleReads':counts,'transitiveReads':len(reads),'nativeWindowActions':0}
 positive=run_gate(capture); faults=[]
 def with_role(role,obj):
  d=dict(raw); d[role]=canon(obj); return d
 own_bad=copy.deepcopy(owned); own_bad['pid']+=1; faults.append(run_gate(capture,with_role('owned',own_bad),'wrong-pid'))
 obs_bad=copy.deepcopy(obs); obs_bad['hwnd']+=1; faults.append(run_gate(capture,with_role('observation',obs_bad),'wrong-hwnd'))
 out_bad=copy.deepcopy(parsed['outcome']); out_bad['cleanup']=copy.deepcopy(out_bad['cleanup']); out_bad['cleanup']['kernelExitSignaled']=False; faults.append(run_gate(capture,with_role('outcome',out_bad),'bad-terminal-certificate'))
 stdout_bad=dict(raw); stdout_bad['stdout']=raw['stdout']+b'control-only-raw-closure-fault'; faults.append(run_gate(capture,stdout_bad,'raw-closure-mismatch'))
 # Independent production compile predicates & exact compiler transport.
 checks=[]; req=plan['compileRequest']; checks += [
  {'name':'production-argv','pass':compile_record['argv']==gate._production_compile_argv(req)},
  {'name':'compiler-bytes','pass':dig(compiler)==('sha256:'+compile_record['compilerHash']) and len(compiler)==compiler_meta['sourceRef']['bytes']},
  {'name':'compiler-ref','pass':compiler_meta['sourceRef']['path']==plan['compilerPath'] and compiler_meta['sourceRef']['sha256']==compile_record['compilerHash']},
  {'name':'all-runtime-tree-bytes','pass':all(p.exists() and dig(p.read_bytes())==expected for p,expected in runtime.values())},
 ]
 result={'schema':'windows-exit-proof-source-control-r2','status':'blocked','controlOnly':True,'nativeWindowActions':0,'productionAdmission':False,'parityClaim':False,'derivedObservationFixture':{'ownedIdentity':owned,'hwnd':close['hwnd'],'rawPreserved':True,'controlOnly':True},'proofRoles':list(ROLES),'positive':positive,'faults':faults,'compileAndArchiveChecks':checks,'compilerArchive':{'path':compiler_meta['physicalPath'],'sha256':dig(compiler),'bytes':len(compiler),'actions':0},'remainingIssues':positive['issues']}
 if a.output.exists(): raise ValueError('output must be fresh')
 a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n'); print(json.dumps({'positive':positive,'faults':faults,'checks':checks},sort_keys=True)); return 0
if __name__=='__main__': raise SystemExit(main())
