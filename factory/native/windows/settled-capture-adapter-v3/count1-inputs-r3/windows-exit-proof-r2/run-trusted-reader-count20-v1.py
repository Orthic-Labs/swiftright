#!/usr/bin/env python3
"""Run F10 Windows guard through ArchiveByteReader over exact proof bytes."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path
from factory.core.artifacts import canonical_hash
from factory.gate.windows_exit_admission import verify_windows_exit_admission
from factory.pipeline.archive_reader import ArchiveByteReader, ArchiveReadError

def digest(raw): return 'sha256:'+hashlib.sha256(raw).hexdigest()
def load(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--proof-bundle',type=Path,required=True); ap.add_argument('--archive-root',type=Path,required=True); ap.add_argument('--output',type=Path,required=True); args=ap.parse_args(); root=Path('.').resolve(); bundle=load(args.proof_bundle); captures=bundle.get('captures',[]); bindings=bundle.get('archiveBindings',{})
 if len(captures)!=20 or bundle.get('status')!='proofs-attached': raise ValueError('strict Count20 proof bundle required')
 maps={}; rows=[]
 for i,capture in enumerate(captures,1):
  key=canonical_hash(capture).removeprefix('sha256:'); source_rows=bindings.get(str(i));
  if not isinstance(source_rows,dict) or not source_rows: raise ValueError('archive bindings missing:'+str(i))
  dest=args.archive_root/f'capture-{key}'; dest.mkdir(parents=True,exist_ok=True)
  for rel,entry in source_rows.items():
   src=Path(entry['sourcePath']).resolve(strict=True); raw=src.read_bytes()
   if digest(raw)!=entry['sha256'] or len(raw)!=entry['bytes']: raise ValueError('source binding drift:'+rel)
   target=dest/rel; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(raw)
  maps[key]=dest
  reader=ArchiveByteReader(windows_archives=maps)
  result=verify_windows_exit_admission(capture,read_bytes=lambda path, c=capture: reader(capture=c,reference=path))
  rows.append(result)
 if not all(x.get('status')=='pass' for x in rows): raise ValueError('production reader rejected proof bundle')
 # Reader fault: one bound proof hash is changed; guard must block before any action.
 fault=json.loads(json.dumps(captures[0])); fault['meta']['conditions']['windowsExitProof']['files']['outcome']['hash']='sha256:'+'0'*64
 fault_key=canonical_hash(fault).removeprefix('sha256:'); fault_reader=ArchiveByteReader(windows_archives={fault_key:maps[canonical_hash(captures[0]).removeprefix('sha256:')]})
 fault_result=verify_windows_exit_admission(fault,read_bytes=lambda path: fault_reader(capture=fault,reference=path))
 if fault_result.get('status')=='pass': raise ValueError('tampered proof accepted')
 out={'schema':'windows-exit-proof-trusted-reader-count20-v1','status':'reader-verified','count':20,'proofBundle':str(args.proof_bundle),'archiveRoot':str(args.archive_root),'rows':rows,'faults':{'tampered-proof-hash':{'status':fault_result.get('status'),'issues':fault_result.get('issues',[]) }},'nativeActions':0,'lockActions':0,'qualification':'windows-origin-proof-reader-verified; parity/golden/freeze-held'}
 if args.output.exists(): raise ValueError('output must be fresh')
 args.output.parent.mkdir(parents=True,exist_ok=True); args.output.write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
 print(json.dumps({'status':out['status'],'count':20,'passed':sum(x.get('status')=='pass' for x in rows),'fault':fault_result.get('status'),'nativeActions':0,'lockActions':0}))
if __name__=='__main__': main()
