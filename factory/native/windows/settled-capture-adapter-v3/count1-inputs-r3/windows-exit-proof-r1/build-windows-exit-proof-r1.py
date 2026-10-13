#!/usr/bin/env python3
"""Attach production Windows exit proofs to actual typed captures.

Every proof binding comes from fetched raw bytes. Missing closure bytes produce
blocked diagnostics; no proof, hash, or pass label is synthesized.
"""
from __future__ import annotations
import argparse, hashlib, json, re
from pathlib import Path, PurePosixPath

ROLES = ('outcome','observation','owned','close','plan','compile','witness','exe','renderer',
         'runtimeReceipt','runtimeTree','stdout','stderr')
# Production gate has 19 roles; compiler is consumed separately from tool/compiler.bin,
# while host/runtime/raw files are transitive bindings outside proof.files.
ALL_ROLES = ('outcome','observation','owned','close','plan','compile','witness','exe','renderer',
             'runtimeReceipt','runtimeTree','stdout','stderr')

def sha(raw: bytes) -> str:
    return 'sha256:' + hashlib.sha256(raw).hexdigest()

def parse(path: Path):
    return json.loads(path.read_bytes().decode('utf-8-sig'))

def safe(value: str) -> bool:
    p=PurePosixPath(value)
    return bool(value) and not p.is_absolute() and '..' not in p.parts and ':' not in value and '\\' not in value and str(p)==value

def ref(value, root: Path) -> tuple[Path,str,int]:
    if isinstance(value,str): p=root/value
    elif isinstance(value,dict) and isinstance(value.get('path'),str): p=root/value['path']
    else: raise ValueError('source ref shape')
    p=p.resolve(strict=True); raw=p.read_bytes(); return p,sha(raw),len(raw)

def run_ref(run, role, inputs, root):
    if role in run: return ref(run[role],root)
    if role in inputs.get('roles',{}): return ref(inputs['roles'][role],root)
    raise ValueError(f'missing source role:{role}')

def source_ref(inputs, key, root):
    value=(inputs.get('source') or {}).get(key)
    if value is None: raise ValueError(f'missing source:{key}')
    return ref(value,root)

def add_binding(bindings, archive_path, source_path, digest, size):
    if not safe(archive_path): raise ValueError(f'unsafe archive path:{archive_path}')
    if archive_path in bindings: raise ValueError(f'duplicate archive path:{archive_path}')
    bindings[archive_path]={'sourcePath':str(source_path),'sha256':digest,'bytes':size}

def build(args):
    root=args.source_root.resolve(strict=True)
    inputs=parse(args.input_map)
    payload=parse(args.captures)
    captures=payload.get('captures') if isinstance(payload,dict) else payload
    if not isinstance(captures,list): raise ValueError('captures list required')
    count=len(captures)
    if count == 0: raise ValueError('adapter typed captures unavailable: typedStatus held; no exit proof attached')
    if count not in (1,20): raise ValueError('expected Count1 or Count20 captures')
    if len(inputs.get('runs',[])) != count: raise ValueError('source map run count mismatch')
    compiler=None
    if args.compiler:
        compiler=ref(parse(args.compiler) if args.compiler.suffix=='.json' else args.compiler,root)
    elif args.require_complete:
        raise ValueError('missing source role:compiler tool bytes required for archive tool/compiler.bin')
    output={'schema':'windows-exit-proof-bundle-v1','status':'blocked','typedStatus':payload.get('typedStatus') if isinstance(payload,dict) else None,'captures':[],'archiveBindings':{},'issues':[]}
    for index,capture in enumerate(captures,1):
        try:
            if not isinstance(capture,dict) or capture.get('platform')!='windows': raise ValueError(f'run{index}: Windows capture required')
            run=inputs['runs'][index-1]
            bindings={}; proof_files={}; archive={}
            for role in ALL_ROLES:
                path,digest,size=run_ref(run,role,inputs,root)
                dest=f'run-{index:03d}/roles/{role}.raw'
                add_binding(archive,dest,path,digest,size)
                proof_files[role]={'path':dest,'hash':digest}
            # Compiler tool is mandatory for production admission; never infer it from exe.
            if compiler:
                cpath,cdigest,csize=compiler;add_binding(archive,'run-%03d/tool/compiler.bin'%index,cpath,cdigest,csize)
            else:
                raise ValueError('missing source role:compiler tool bytes required for archive tool/compiler.bin')
            # Host source closure comes directly from plan.sourceBindings.
            plan_path,_,_=run_ref(run,'plan',inputs,root); plan=parse(plan_path)
            for binding in plan.get('sourceBindings',[]):
                rel=binding.get('path'); expected='sha256:'+str(binding.get('sha256','')).removeprefix('sha256:')
                if not isinstance(rel,str): raise ValueError(f'run{index}: invalid plan source binding')
                p,digest,size=source_ref(inputs,rel,root)
                if digest != expected: raise ValueError(f'run{index}: source byte mismatch:{rel}')
                add_binding(archive,f'run-{index:03d}/host/{rel}',p,digest,size)
            # Runtime tree rows bind exact module bytes; source map names are explicit.
            tree_path,_,_=source_ref(inputs,'runtime-source-tree.json',root); tree=parse(tree_path)
            if not isinstance(tree,list) or not tree: raise ValueError(f'run{index}: runtime tree missing')
            for item in tree:
                rel=item.get('path'); expected='sha256:'+str(item.get('sha256','')).removeprefix('sha256:')
                mod=(inputs.get('runtimeModules') or {}).get(item.get('archivePath'))
                if not isinstance(mod,dict): raise ValueError(f'run{index}: runtime module source missing:{item.get("archivePath")}')
                p,digest,size=ref(mod,root)
                if digest != expected: raise ValueError(f'run{index}: runtime module byte mismatch:{rel}')
                add_binding(archive,f'run-{index:03d}/runtime/{rel}',p,digest,size)
            # Observation raw-file rows need actual fetched compile streams; absence stays blocked.
            obs_path,_,_=run_ref(run,'observation',inputs,root); obs=parse(obs_path)
            for item in obs.get('files',[]):
                rel=item.get('path'); expected='sha256:'+str(item.get('sha256','')).removeprefix('sha256:')
                candidate=obs_path.parent/rel
                if not candidate.is_file(): raise ValueError(f'run{index}: raw closure file unavailable:{rel}')
                p,digest,size=ref(str(candidate.relative_to(root)),root)
                if digest != expected: raise ValueError(f'run{index}: raw closure byte mismatch:{rel}')
                add_binding(archive,f'run-{index:03d}/raw/{rel}',p,digest,size)
            proof={'version':1,'files':{role:proof_files[role] for role in ('outcome','observation','owned','close','plan','compile','witness','exe','renderer','runtimeReceipt','runtimeTree','stdout','stderr')}}
            # Gate requires 19 roles. Keep compiler/tool & host/runtime/raw bindings outside proof.files.
            if len(proof['files']) != 13: raise ValueError('internal proof role set incomplete')
            enriched=json.loads(json.dumps(capture)); conditions=enriched.setdefault('meta',{}).setdefault('conditions',{}); conditions['windowsExitProof']=proof
            output['captures'].append(enriched); output['archiveBindings'][str(index)]=archive
        except (ValueError,KeyError,TypeError,OSError) as exc:
            output['issues'].append(str(exc))
    if output['issues']:
        output['captures']=[]; output['status']='blocked'
    else:
        output['status']='proofs-attached'; output['typedStatus']='normalized-observational'
    if args.output.exists(): raise ValueError('output must be fresh')
    args.output.parent.mkdir(parents=True,exist_ok=True); args.output.write_text(json.dumps(output,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    return output

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--captures',type=Path,required=True);ap.add_argument('--input-map',type=Path,required=True);ap.add_argument('--source-root',type=Path,default=Path('.'));ap.add_argument('--compiler',type=Path);ap.add_argument('--require-complete',action='store_true');ap.add_argument('--output',type=Path,required=True);args=ap.parse_args()
    try: result=build(args)
    except Exception as exc: print(json.dumps({'status':'blocked','issues':[str(exc)]},sort_keys=True)); return 2
    print(json.dumps({'status':result['status'],'proofCount':len(result['captures']),'issues':result['issues']},sort_keys=True)); return 0 if result['status']=='proofs-attached' else 2
if __name__=='__main__': raise SystemExit(main())
