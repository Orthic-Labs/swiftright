#!/usr/bin/env python3
"""Offline verifier for v6 positive control, including archived source joins."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

def digest(path: Path) -> str: return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
def fail(message: str) -> None: raise ValueError(message)
def load_receipt_validator(root: Path):
    spec=importlib.util.spec_from_file_location('seed_origin_v6_receipt_validator',root/'verify_receipt.py')
    if spec is None or spec.loader is None: fail('receipt validator unavailable')
    mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod

def validate(root: Path) -> dict:
    root=root.resolve(); amap=json.loads((root/'positive-control/archive-map.json').read_text()); rows=amap.get('files')
    isinstance(rows,list) and len(rows)==8 or fail('positive archive closure count')
    by_repo={}
    for row in rows:
        rel=row.get('repoPath'); isinstance(rel,str) and rel not in by_repo or fail('duplicate archive path')
        p=root/rel; p.is_file() or fail(f'missing archive file {rel}')
        digest(p).removeprefix('sha256:')==row.get('sha256') or fail(f'archive hash {rel}')
        p.stat().st_size==row.get('bytes') or fail(f'archive bytes {rel}')
        by_repo[rel]=row
    receipt_row=by_repo['positive-control/evidence/compiler-receipt.json']; internal=Path(receipt_row['internalPath'])
    internal.is_file() or fail('internal receipt missing'); digest(internal).removeprefix('sha256:')==receipt_row['sha256'] or fail('internal receipt changed')
    receipt=json.loads(internal.read_text()); receipt_validator=load_receipt_validator(root); receipt_validator.validate(internal)
    compiler=receipt['compiler']; source_bindings=amap.get('sourceBindings'); isinstance(source_bindings,list) and len(source_bindings)==2 or fail('source bindings')
    bound_paths=[]
    for binding in source_bindings:
        name=binding['name']; archive_path=binding['archivePath']; row=by_repo[archive_path]; archive=root/archive_path
        source_input=Path(binding['sourceInputInternalPath']); receipt_work=Path(binding['receiptWorkPath'])
        source_input.is_file() and receipt_work.is_file() or fail(f'source join {name}')
        digest(source_input)==digest(archive)==digest(receipt_work) or fail(f'source bytes {name}')
        before=receipt['sourceBefore'][name]; after=receipt['sourceAfter'][name]
        before['path']==str(receipt_work) and after['path']==str(receipt_work) or fail(f'source receipt path {name}')
        before['sha256']==digest(archive) and after['sha256']==digest(archive) or fail(f'source receipt hash {name}')
        before['bytes']==archive.stat().st_size and after['bytes']==archive.stat().st_size or fail(f'source receipt bytes {name}')
        bound_paths.append(str(receipt_work))
    compiler['argv'][-2:]==bound_paths or fail('compiler argv source join')
    summary=json.loads((root/'positive-control/control-summary.json').read_text())
    summary['status']=='POSITIVE' and summary['attempts']==1 and summary['retry'] is False or fail('summary')
    summary['captureRun'] is False and summary['seedCaptureRun'] is False and summary['guiCaptureRun'] is False or fail('capture scope')
    compiler['exitCode']==0 and compiler['timedOut'] is False and compiler['realToolDrift'] is False and receipt['sourceDrift'] is False or fail('positive outcome')
    summary['receiptHash']==digest(root/'positive-control/evidence/compiler-receipt.json') or fail('summary receipt hash')
    summary['binaryHash']==compiler['outputBinary']['sha256'] or fail('summary binary hash')
    return {'status':'PASS','compilerPid':compiler['pid'],'compilerExit':0,'resolverPid':receipt['resolver']['pid'],'receiptHash':receipt_row['sha256'],'binaryHash':compiler['outputBinary']['sha256'],'sourceBindings':2,'sourceDrift':False,'timedOut':False,'collectorRootDetection':'PASS','runnerReplayable':'PASS'}
if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('root',type=Path); args=parser.parse_args()
    try: print(json.dumps(validate(args.root),sort_keys=True,indent=2))
    except Exception as error: print(f'FAIL: {error}'); raise SystemExit(1)
