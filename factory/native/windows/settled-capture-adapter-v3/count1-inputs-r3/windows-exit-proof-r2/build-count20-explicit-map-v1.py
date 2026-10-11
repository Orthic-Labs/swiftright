#!/usr/bin/env python3
"""Build strict Count20 proof inputs from v6 map & archived r7 bytes."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

ROLES = ('outcome','observation','owned','close','plan','compile','witness','exe','renderer','runtimeReceipt','runtimeTree','stdout','stderr')
ROLE_PATHS = {'outcome':'capture-outcome.json','observation':'native-observation.json','owned':'owned-process.json','close':'owned-close.json','plan':'plan.json','compile':'observation.json','witness':'Witness.swift','exe':'FactoryProbe.exe','renderer':'swiftright_render.dll','runtimeReceipt':'runtime-source-receipt.json','runtimeTree':'runtime-source-tree.json','stdout':'host.stdout.txt','stderr':'host.stderr.txt'}
def load(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):
 b=Path(p).read_bytes(); return 'sha256:'+hashlib.sha256(b).hexdigest(),len(b)
def ref(root,v):
 if not isinstance(v,dict) or not isinstance(v.get('path'),str): raise ValueError('ref shape')
 p=(root/v['path']).resolve(); p.relative_to(root.resolve())
 d,n=sha(p)
 if d!=v.get('sha256') or n!=v.get('bytes'): raise ValueError('ref drift:'+v['path'])
 return {'path':v['path'],'sha256':d,'bytes':n}
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--source-root',type=Path,default=Path('.')); ap.add_argument('--actual-map',type=Path,required=True); ap.add_argument('--adapter-inputs',type=Path,required=True); ap.add_argument('--compiler-ref',type=Path,required=True); ap.add_argument('--output',type=Path,required=True); args=ap.parse_args(); root=args.source_root.resolve()
 actual=load(args.actual_map); adapter=load(args.adapter_inputs); runs=adapter.get('runs',[])
 if len(runs)!=20 or actual.get('count')!=20: raise ValueError('Count20 map required')
 source=adapter['source']; roles=adapter['roles']; bound=[]
 role_values=[{'outcome':r['outcome'],'observation':r['observation'],'owned':r['owned'],'close':r['close'],'plan':roles['plan'],'compile':roles['compile'],'witness':source['Sources/FactoryProbe/Witness.swift'],'exe':roles['exe'],'renderer':roles['renderer'],'runtimeReceipt':source['runtime-source-receipt.json'],'runtimeTree':source['runtime-source-tree.json'],'stdout':r['stdout'],'stderr':r['stderr']} for r in runs]
 bound_runs=[]
 for rv in role_values: bound_runs.append({k:ref(root,v) for k,v in rv.items()})
 plan=load(root/bound_runs[0]['plan']['path']); compile=load(root/bound_runs[0]['compile']['path']); tree=load(root/bound_runs[0]['runtimeTree']['path']); receipt=load(root/bound_runs[0]['runtimeReceipt']['path'])
 if not isinstance(tree,list) or len(tree)!=21: raise ValueError('runtime tree must contain 21 rows')
 host=[]
 for row in plan['sourceBindings']:
  item=ref(root,source[row['path']]);
  if item['sha256']!=row['sha256']: raise ValueError('host source mismatch:'+row['path'])
  host.append({'path':row['path'],'source':item})
 runtime=[]; runtime_root=Path('factory/native/windows/module-origin-37429120-20261011/runtime')
 for row in tree:
  rel=row['path']; p=runtime_root/rel; d,n=sha(root/p); item={'path':str(p),'sha256':d,'bytes':n}
  if d!=row['sha256']: raise ValueError('runtime source mismatch:'+rel)
  runtime.append({'path':rel,'source':item,'sha256':row['sha256']})
 modules={k:ref(root,v) for k,v in adapter['runtimeModules'].items()}
 compiler_ref=load(root/args.compiler_ref); compiler=ref(root,compiler_ref)
 # Verify every native role is archived; 24 raw rows/run are required.
 raw=[]
 for rv in bound_runs:
  idx=len(raw)+1
  obs_all=load(root/rv['observation']['path']); obs=obs_all[idx-1] if isinstance(obs_all,list) else obs_all
  native_dir=Path(rv['observation']['path']).parent/('native-'+str(obs.get('index',idx)).zfill(2))
  # Native observation in r7 is aggregate; bind each run's own native-NN folder.
  native_dir=Path(rv['observation']['path']).parent/f'native-{idx:02d}'
  rows=obs.get('files',[])
  if len(rows)!=24: raise ValueError(f'raw role count:{idx}')
  one=[]
  for row in rows:
   rp=native_dir/row['path']; d,n=sha(root/rp); expected='sha256:'+str(row['sha256']).removeprefix('sha256:')
   if d!=expected: raise ValueError('native raw mismatch:'+str(rp))
   one.append({'path':row['path'],'source':{'path':str(rp),'sha256':d,'bytes':n},'sha256':d})
  raw.append(one)
 out={'schema':'windows-exit-proof-explicit-inputs-count20-v1','status':'source-bound','actualMap':str(args.actual_map),'adapterInputs':str(args.adapter_inputs),'runs':bound_runs,'roles':{k:ref(root,v) for k,v in {'plan':roles['plan'],'compile':roles['compile'],'witness':source['Sources/FactoryProbe/Witness.swift'],'exe':roles['exe'],'renderer':roles['renderer'],'runtimeReceipt':source['runtime-source-receipt.json'],'runtimeTree':source['runtime-source-tree.json']}.items()},'hostSourceBindings':host,'runtimeTreeBindings':runtime,'runtimeModules':modules,'compiler':compiler,'compilerRef':str(args.compiler_ref),'nativeObservationRaw':raw,'sourceFacts':{'runtimeSourceCommit':receipt['sourceCommit'],'runtimeSourceTreeHash':receipt['sourceTreeHash'],'runtimeTreeRows':21,'hostRows':len(host),'nativeRawRows':sum(map(len,raw)),'runtimeModuleRows':len(modules),'count':20}}
 if args.output.exists(): raise ValueError('output must be fresh')
 args.output.parent.mkdir(parents=True,exist_ok=True); args.output.write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
 print(json.dumps({'status':out['status'],'count':20,'hostRows':len(host),'runtimeRows':21,'nativeRawRows':sum(map(len,raw))}))
if __name__=='__main__': main()
