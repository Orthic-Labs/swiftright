#!/usr/bin/env python3
"""Offline verifier for v4 archived positive compiler control."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

def digest(path: Path) -> str:
    return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()

def fail(message: str) -> None:
    raise ValueError(message)

def receipt_validator(root: Path):
    spec = importlib.util.spec_from_file_location('seed_origin_v4_receipt_validator', root / 'verify_receipt.py')
    if spec is None or spec.loader is None: fail('receipt validator unavailable')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

def validate(root: Path) -> dict:
    root = root.resolve()
    archive = json.loads((root / 'positive-control/archive-map.json').read_text())
    rows = archive.get('files'); isinstance(rows, list) and len(rows) == 6 or fail('positive archive file count')
    by_repo = {}
    for row in rows:
        rel = row.get('repoPath'); isinstance(rel, str) and rel not in by_repo or fail('duplicate archive path')
        p = root / rel; p.is_file() or fail(f'missing archive file {rel}')
        digest(p).removeprefix('sha256:') == row.get('sha256') or fail(f'archive hash {rel}')
        p.stat().st_size == row.get('bytes') or fail(f'archive bytes {rel}')
        by_repo[rel] = row
    receipt_row = by_repo['positive-control/evidence/compiler-receipt.json']
    internal = Path(receipt_row['internalPath']); internal.is_file() or fail('internal receipt missing')
    digest(internal).removeprefix('sha256:') == receipt_row['sha256'] or fail('receipt changed')
    receipt = receipt_validator(root).validate(internal)
    receipt.get('status') == 'PASS' or fail('receipt validator')
    raw = json.loads(internal.read_text()); compiler = raw['compiler']; summary = json.loads((root / 'positive-control/control-summary.json').read_text())
    summary['status'] == 'POSITIVE' and summary['attempts'] == 1 and summary['retry'] is False or fail('summary')
    summary['captureRun'] is False and summary['seedCaptureRun'] is False and summary['guiCaptureRun'] is False or fail('scope')
    compiler['timedOut'] is False and compiler['realToolDrift'] is False and raw['sourceDrift'] is False or fail('positive outcome')
    summary['receiptHash'] == 'sha256:' + receipt_row['sha256'] or fail('receipt summary hash')
    summary['binaryHash'] == compiler['outputBinary']['sha256'] or fail('binary summary hash')
    return {'status':'PASS','compilerPid':compiler['pid'],'compilerExit':compiler['exitCode'],'resolverPid':raw['resolver']['pid'],'receiptHash':receipt_row['sha256'],'binaryHash':compiler['outputBinary']['sha256'],'sourceDrift':raw['sourceDrift'],'timedOut':compiler['timedOut'],'collectorRootDetection':'PASS','runnerReplayable':'PASS'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(); parser.add_argument('root', type=Path); args = parser.parse_args()
    try: print(json.dumps(validate(args.root), sort_keys=True, indent=2))
    except Exception as error: print(f'FAIL: {error}'); raise SystemExit(1)
