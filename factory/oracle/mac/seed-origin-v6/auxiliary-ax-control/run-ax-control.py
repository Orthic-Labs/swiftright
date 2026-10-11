#!/usr/bin/env python3
"""One owned AXClient compiler control; preflight is read-only and no GUI starts."""
from __future__ import annotations
import argparse
import importlib.util
import json
import os
from pathlib import Path

def main() -> int:
    parser=argparse.ArgumentParser(); parser.add_argument('--scratch',required=True,type=Path); args=parser.parse_args()
    scratch=args.scratch.expanduser().resolve(); allowed=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory').resolve()
    scratch != allowed and scratch.is_relative_to(allowed) or parser.error('scratch must be fresh internal cache child')
    if scratch.exists(): parser.error('scratch already exists; refusing output overwrite')
    scratch.mkdir(parents=True); evidence=scratch/'evidence'; evidence.mkdir()
    module_path=Path(__file__).resolve().parents[1]/'capture_origin.py'
    spec=importlib.util.spec_from_file_location('seed_origin_v6_ax_collector',module_path)
    if spec is None or spec.loader is None: raise RuntimeError('collector unavailable')
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    info=module.fresh_ax_preflight(scratch,evidence)
    info['controlScope']='compile + read-only AXIsProcessTrusted preflight; no GUI capture'
    info['attempts']=1; info['retry']=False; info['seedCaptureRun']=False; info['guiCaptureRun']=False
    (evidence/'ax-control-summary.json').write_text(json.dumps(info,sort_keys=True,indent=2)+'\n')
    print(json.dumps(info,sort_keys=True),flush=True)
    return 0 if info.get('compilerStatus') == 'SUCCESS' else 1
if __name__=='__main__': raise SystemExit(main())
