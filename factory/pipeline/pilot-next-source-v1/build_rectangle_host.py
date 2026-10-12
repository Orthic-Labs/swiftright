#!/usr/bin/env python3
"""Bounded source-only host builder; root runs it on internal Mac disk."""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, subprocess, time
from pathlib import Path

MAX_FILE = 64 * 1024 * 1024
REPO = Path(__file__).resolve().parents[3]
PACKET = Path(__file__).resolve().parent
HARNESS = REPO / 'factory/oracle/mac/padding-origin-r11-source-v1/CaptureHost.swift'


def digest(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_FILE:
        raise ValueError(f'bounded regular file required: {path}')
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024): h.update(chunk)
    return 'sha256:' + h.hexdigest()


def bounded_json(path: Path):
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > 2 * 1024 * 1024:
        raise ValueError(f'bounded regular JSON required: {path}')
    return json.loads(path.read_bytes())


def internal_output(path: Path) -> Path:
    root = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory').resolve()
    value = path.expanduser().resolve()
    if not value.is_relative_to(root) or value == root:
        raise ValueError('output must be fresh internal SwiftRightFactory child')
    if value.exists() and any(value.iterdir()):
        raise ValueError('output must be fresh')
    return value


def run_bounded(argv: list[str], cwd: Path, out: Path, timeout: int) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    stdout_path, stderr_path = out / 'compiler.stdout.bin', out / 'compiler.stderr.bin'
    started = time.time()
    with stdout_path.open('wb') as stdout, stderr_path.open('wb') as stderr:
        process = subprocess.Popen(argv, cwd=str(cwd), stdout=stdout, stderr=stderr, close_fds=True)
        timed_out = False
        while process.poll() is None:
            if time.time() - started >= timeout:
                timed_out = True
                process.terminate()
                try: process.wait(10)
                except subprocess.TimeoutExpired:
                    process.kill(); process.wait(10)
                break
            time.sleep(0.25)
        exit_code = process.returncode
    receipt = {
      'argv': argv, 'pid': process.pid, 'startNewSession': False,
      'timeoutSeconds': timeout, 'timedOut': timed_out, 'exitCode': exit_code,
      'stdoutPath': str(stdout_path), 'stderrPath': str(stderr_path),
      'stdoutBytes': stdout_path.stat().st_size, 'stderrBytes': stderr_path.stat().st_size,
      'stdoutSha256': digest(stdout_path), 'stderrSha256': digest(stderr_path),
      'streamsSealed': True, 'sealOrder': 'process-exit,close-stream-files,then-size-hash'
    }
    return receipt


def build_host(output: Path, *, expected_hash: str | None = None, case: dict | None = None, manifest: dict | None = None) -> dict:
    out = internal_output(output); out.mkdir(parents=True); work = out / 'work'; evidence = out / 'evidence'; work.mkdir(); evidence.mkdir()
    source = PACKET / 'witness.swift'
    if digest(source) != 'sha256:5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d': raise ValueError('packet witness hash drift')
    shutil.copy2(source, work / 'Witness.swift'); shutil.copy2(HARNESS, work / 'CaptureHost.swift')
    harness = work / 'CaptureHost.swift'; harness.write_text(harness.read_text().replace('__WITNESS_TYPE__', 'Witness_shapes_rectangle_fill').replace('window.makeKeyAndOrderFront(nil)', 'window.orderBack(nil)'))
    resolver = run_bounded(['/usr/bin/xcrun', '--find', 'swiftc'], work, evidence / 'resolve', 30)
    resolver_stdout = evidence / 'resolve' / 'compiler.stdout.bin'
    if resolver['timedOut'] or resolver['exitCode'] != 0: raise RuntimeError('swiftc resolver failed')
    swiftc = resolver_stdout.read_text(errors='replace').strip().splitlines()[-1]
    # Keep xcrun wrapper: direct swiftc misses SDK selection on fresh internal-disk builds.
    compiler = run_bounded(['/usr/bin/xcrun', 'swiftc', '-parse-as-library', '-O', '-o', str(work / 'capture-host'), str(work / 'Witness.swift'), str(work / 'CaptureHost.swift')], work, evidence / 'compile', 180)
    binary = work / 'capture-host'
    status = 'SUCCESS' if compiler['exitCode'] == 0 and not compiler['timedOut'] and binary.is_file() else 'FAILED'
    payload = {
      'schema':'factory-macos-pilot-next-host-build-receipt-v2','status':status,
      'candidate':'swiftui.shapes.rectangle-fill.pilot-next','case':manifest.get('case') if manifest else None,
      'tupleId':case.get('tuple',{}).get('id') if case else None,
      'source':{'path':str(source),'sha256':digest(source),'bytes':source.stat().st_size},
      'adapter':{'path':str(harness),'sha256':digest(harness),'bytes':harness.stat().st_size},
      'compiler':{'path':swiftc,'resolver':resolver,'receipt':compiler},
      'binary':{'path':str(binary),'sha256':digest(binary),'bytes':binary.stat().st_size} if binary.is_file() else None,
      'expectedBinaryHash':expected_hash,'hashMatch':None if expected_hash is None or not binary.is_file() else digest(binary) == expected_hash,
      'effects':{'nativeWindowActions':0,'compilerActions':1,'remoteActions':0,'lockActions':0}
    }
    (out / 'host-build-r1.json').write_text(json.dumps(payload,sort_keys=True,indent=2)+'\n')
    if status != 'SUCCESS' or payload['hashMatch'] is False: raise RuntimeError('source-bound host build failed or hash drifted')
    return payload


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument('--output', type=Path, required=True); ap.add_argument('--expected-binary-hash')
    args = ap.parse_args()
    payload = build_host(args.output, expected_hash=args.expected_binary_hash)
    print(json.dumps({'status':payload['status'],'binary':payload['binary'],'effects':payload['effects']},sort_keys=True)); return 0
if __name__ == '__main__': raise SystemExit(main())
