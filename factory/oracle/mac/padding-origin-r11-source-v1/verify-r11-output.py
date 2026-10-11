#!/usr/bin/env python3
"""Verify fresh Mac20 output binds to source-bound r11 case & tuple."""
from __future__ import annotations
import argparse, hashlib, json
import sys
from pathlib import Path

for candidate in Path(__file__).resolve().parents:
    if (candidate / 'factory/core/artifacts.py').is_file():
        sys.path.insert(0, str(candidate))
        break
from factory.core.artifacts import canonical_hash, validate_artifact

def digest(p: Path) -> str:
    return 'sha256:' + hashlib.sha256(p.read_bytes()).hexdigest()

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument('--output',type=Path,required=True)
    ap.add_argument('--case',type=Path,required=True)
    ap.add_argument('--manifest',type=Path,required=True)
    args=ap.parse_args()
    case=json.loads(args.case.read_text()); manifest=json.loads(args.manifest.read_text())
    validate_artifact(case)
    case_hash=canonical_hash(case); case_ref={'id':case['id'],'hash':case_hash}
    if manifest.get('case') != case_ref: raise SystemExit('manifest case ref mismatch')
    tuple_id=case['tuple'].get('id','')
    if not tuple_id.startswith('sr1-source-bound-r11-mac20-host-') or not tuple_id.endswith('-20261011'):
        raise SystemExit('tuple id is not fresh host-bound r11')
    if '.r11.h' not in case.get('id',''):
        raise SystemExit('case id is not fresh host-bound r11')
    expected_host=case['tuple']['hostHashes']['macos']
    summary_path=args.output/case['id']/ 'summary.json'
    if not summary_path.is_file(): raise SystemExit(f'missing summary: {summary_path}')
    summary=json.loads(summary_path.read_text())
    if summary.get('status') != 'CANDIDATE_CAPTURED' or summary.get('candidateOnly') is not True: raise SystemExit('capture is not candidate-complete')
    if summary.get('case',{}).get('id') != case['id'] or summary.get('case',{}).get('hash') != case_hash: raise SystemExit('summary case binding mismatch')
    if summary.get('binaryHash') != expected_host: raise SystemExit('compiled Mac host hash differs from tuple hostHashes.macos')
    if summary.get('sourceHash') != manifest.get('sourceHash'): raise SystemExit('source hash drift')
    runs=summary.get('runs')
    if not isinstance(runs,list) or len(runs)!=20: raise SystemExit('requires exactly 20 runs')
    capture_ids=[]
    for i,row in enumerate(runs,1):
        if row.get('run') != i: raise SystemExit(f'run order mismatch: {i}')
        p=args.output/case['id']/f'run-{i:03d}'/'capture.json'
        if not p.is_file(): raise SystemExit(f'missing capture: {p}')
        capture=json.loads(p.read_text()); validate_artifact(capture)
        if capture.get('case') != case_ref or capture.get('tuple') != case['tuple'] or capture.get('platform') != 'macos' or capture.get('meta',{}).get('run') != i:
            raise SystemExit(f'capture binding mismatch: {i}')
        if capture.get('meta',{}).get('host',{}).get('hash') != expected_host: raise SystemExit(f'host binding mismatch: {i}')
        capture_ids.append(capture['id'])
    if len(set(capture_ids)) != 20: raise SystemExit('capture IDs not unique')
    print(json.dumps({'status':'r11-mac20-source-bound','case':case_ref,'tupleID':case['tuple']['id'],'runs':20,'hostHash':expected_host,'effects':{'nativeWindowActions':20,'compilerActions':1,'remoteActions':0,'lockActions':0}}))
if __name__=='__main__': main()
