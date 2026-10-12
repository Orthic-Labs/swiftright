#!/usr/bin/env python3
"""Offline source-contract controls; never launches AX, compiler, or host."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

MAX_SOURCE = 1 * 1024 * 1024

def bounded_text(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_SOURCE:
        raise ValueError(f'bounded regular source required: {path}')
    return path.read_text()

def bounded_digest(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_SOURCE:
        raise ValueError(f'bounded regular source required: {path}')
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            h.update(chunk)
    return 'sha256:' + h.hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parent)
    args = ap.parse_args()
    root = args.source_root.resolve()
    py = bounded_text(root / 'capture_origin_rectangle_r1.py')
    swift = bounded_text(root / 'CaptureHost.swift')
    ax = bounded_text(root / 'AXClient.swift')
    checks = {
      'denied_permission_is_held': 'AXIsProcessTrusted()' in ax and 'permissionRequests": false' in ax and 'no-prompt AX trust preflight denied' in ax,
      'screen_permission_is_preflight_only': 'CGPreflightScreenCaptureAccess()' in swift and 'permissionRequests": false' in swift,
      'window_does_not_activate': 'window.orderBack(nil)' in swift and 'makeKeyAndOrderFront' not in swift,
      'children_stay_in_parent_group': 'start_new_session=False' in py and "'processGroupOwned': False" in py and 'parentProcessGroup' in py and 'retainedProcessHandle' in py,
      'cleanup_does_not_kill_parent_group': 'os.killpg' not in py and 'process.terminate()' in py and 'process.kill()' in py,
      'identity_path_and_hash_are_required': "'--owner-path'" in py and "'--owner-hash'" in py and 'proc_pidpath' in ax,
      'identity_mismatch_is_held': 'target owner PID path unavailable' in ax and 'expectedHash' in ax,
      'logs_are_bounded': 'bounded_text' in py and '8 * 1024 * 1024' in py,
    }
    payload = {
      'kind': 'pilot-next-mac-capture-source-controls-v1',
      'status': 'PASS' if all(checks.values()) else 'HELD',
      'controlOnly': True,
      'nativeWindowActions': 0,
      'compilerActions': 0,
      'checks': checks,
      'sources': {
        name: {'path': str(path), 'bytes': path.stat().st_size, 'sha256': bounded_digest(path)}
        for name, path in {'capture': root / 'capture_origin_rectangle_r1.py', 'host': root / 'CaptureHost.swift', 'ax': root / 'AXClient.swift'}.items()
      },
    }
    print(json.dumps(payload, sort_keys=True))
    return 0 if payload['status'] == 'PASS' else 1

if __name__ == '__main__':
    raise SystemExit(main())
