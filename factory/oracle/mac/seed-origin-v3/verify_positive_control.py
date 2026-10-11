#!/usr/bin/env python3
"""Offline verifier for one archived, successful v3 compiler control."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return 'sha256:' + h.hexdigest()

def fail(message: str) -> None:
    raise ValueError(message)

def load_v2_validator(root: Path):
    path = root / 'collector' / 'verify_receipt.py'
    spec = importlib.util.spec_from_file_location('seed_origin_v3_receipt_validator', path)
    if spec is None or spec.loader is None:
        fail('receipt validator unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def validate(root: Path) -> dict:
    root = root.resolve()
    archive = json.loads((root / 'positive-control/archive-map.json').read_text())
    files = archive.get('files')
    isinstance(files, list) and len(files) == 9 or fail('archive file count')
    by_repo = {}
    for row in files:
        repo_path = row.get('repoPath')
        raw_path = row.get('internalPath')
        isinstance(repo_path, str) and repo_path not in by_repo or fail('duplicate archive path')
        isinstance(raw_path, str) or fail('archive internal path')
        copied = root / repo_path
        copied.is_file() or fail(f'missing archive file {repo_path}')
        digest(copied).removeprefix('sha256:') == row.get('sha256') or fail(f'archive hash {repo_path}')
        copied.stat().st_size == row.get('bytes') or fail(f'archive bytes {repo_path}')
        by_repo[repo_path] = row
    receipt_row = by_repo['positive-control/evidence/compiler-receipt.json']
    receipt_hash = receipt_row['sha256']
    receipt_path = Path(receipt_row['internalPath'])
    receipt_path.is_file() or fail('internal receipt missing')
    digest(receipt_path).removeprefix('sha256:') == receipt_hash or fail('internal receipt changed')
    validator = load_v2_validator(root)
    result = validator.validate(receipt_path)
    result.get('status') == 'PASS' or fail('receipt validator did not pass')
    receipt = json.loads(receipt_path.read_text())
    compiler = receipt['compiler']
    summary = json.loads((root / 'positive-control/control-summary.json').read_text())
    summary['status'] == 'POSITIVE' or fail('summary status')
    summary['attempts'] == 1 and summary['retry'] is False or fail('retry policy')
    summary['captureRun'] is False and summary['guiCaptureRun'] is False and summary['seedCaptureRun'] is False or fail('capture scope')
    compiler['exitCode'] == 0 and compiler['timedOut'] is False and compiler['realToolDrift'] is False or fail('compiler outcome')
    compiler['outputBinary']['sha256'] == summary['binaryHash'] or fail('summary binary hash')
    compiler['outputBinary']['bytes'] == summary['binaryBytes'] or fail('summary binary bytes')
    summary['receiptHash'].removeprefix('sha256:') == receipt_hash or fail('summary receipt hash')
    return {
        'status': 'PASS',
        'receiptHash': receipt_hash,
        'compilerPid': compiler['pid'],
        'compilerExit': compiler['exitCode'],
        'resolverPid': receipt['resolver']['pid'],
        'binaryHash': compiler['outputBinary']['sha256'],
        'binaryBytes': compiler['outputBinary']['bytes'],
        'sourceDrift': receipt['sourceDrift'],
        'timedOut': compiler['timedOut'],
        'toolDrift': compiler['realToolDrift'],
        'attempts': 1,
        'seedCaptureRun': False,
    }

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    args = parser.parse_args()
    print(json.dumps(validate(args.root), indent=2, sort_keys=True))
