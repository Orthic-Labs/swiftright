#!/usr/bin/env python3
"""One owned timeout fault control for v6 _safe_drain."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

def repo_root() -> Path:
    injected = os.environ.get('SWIFTRIGHT_REPO_ROOT')
    candidates = [Path(injected).expanduser().resolve()] if injected else []
    candidates.extend(Path(__file__).resolve().parents)
    for candidate in candidates:
        if (candidate / 'factory/core/artifacts.py').is_file() and (candidate / 'factory/oracle').is_dir():
            return candidate
    raise RuntimeError('repository root marker factory/core/artifacts.py not found')

def sha(path: Path) -> str:
    return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--scratch', required=True, type=Path)
    args = parser.parse_args()
    scratch = args.scratch.expanduser().resolve()
    allowed = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory').resolve()
    scratch != allowed and scratch.is_relative_to(allowed) or parser.error('scratch must be fresh internal cache child')
    if scratch.exists(): parser.error('scratch already exists; refusing output overwrite')
    root = repo_root()
    module_path = root / 'factory/oracle/mac/seed-origin-v6/capture_origin.py'
    spec = importlib.util.spec_from_file_location('seed_origin_v6_timeout_collector', module_path)
    if spec is None or spec.loader is None: raise RuntimeError('collector unavailable')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    evidence = scratch / 'evidence'; evidence.mkdir(parents=True)
    command = [sys.executable, '-c', 'import time; time.sleep(30)']
    started = datetime.now(timezone.utc).isoformat()
    process = subprocess.Popen(command, cwd=str(scratch), stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    stdout, stderr, cleanup = module._safe_drain(process, timeout=0.1)
    ended = datetime.now(timezone.utc).isoformat()
    stdout_path = evidence / 'timeout.stdout.txt'; stderr_path = evidence / 'timeout.stderr.txt'
    stdout_path.write_bytes(stdout); stderr_path.write_bytes(stderr)
    receipt = {
        'kind': 'seed-origin-v6-timeout-control', 'version': '1', 'status': 'TIMEOUT', 'attempts': 1,
        'command': command, 'cwd': str(scratch), 'pid': process.pid, 'pgid': process.pid,
        'startedAtUtc': started, 'endedAtUtc': ended, 'exitCode': process.returncode,
        'cleanup': cleanup, 'timedOut': bool(cleanup.get('timedOut') or cleanup.get('drainTimedOut')),
        'stdoutPath': str(stdout_path), 'stderrPath': str(stderr_path), 'stdoutHash': sha(stdout_path), 'stderrHash': sha(stderr_path),
        'collectorPath': str(module_path), 'seedCaptureRun': False, 'guiCaptureRun': False,
    }
    (evidence / 'timeout-receipt.json').write_text(json.dumps(receipt, indent=2, sort_keys=True) + '\n')
    print(json.dumps(receipt, sort_keys=True), flush=True)
    return 0 if receipt['timedOut'] and cleanup.get('termSent') and process.returncode is not None else 1

if __name__ == '__main__':
    raise SystemExit(main())
