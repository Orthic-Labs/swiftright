"""Fetch & archive one completed Windows final-build receipt.

This helper performs no remote mutation, compilation, GUI action, or cleanup.
Root owns invocation from a bounded SSH/SCP session.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT = Path('/Volumes/D/claude/swiftright')
EXEC = ROOT / 'factory/pipeline/pilot-delivery-five-v1/root-execution'
MAX_JSON = 4 * 1024 * 1024
MAX_STREAM = 8 * 1024 * 1024
MAX_EXE = 64 * 1024 * 1024

parser = argparse.ArgumentParser()
parser.add_argument('--host', choices=('image', 'image-star-provider','image-star-observation','stack-overlay-colors','custom-layout-colors','rounded-stroke-boundary','bundled-font-observation', 'rounded-stroke', 'rounded-stroke-centered', 'rounded-stroke-circular', 'rounded-stroke-observation', 'stack-overlay-centered', 'stack-overlay-observation', 'custom-layout-centered', 'custom-layout-observation'), required=True)
parser.add_argument('--phase', choices=('prebuild', 'final'), default='final')
parser.add_argument('--timeout', type=int, default=60)
args = parser.parse_args()
if not 1 <= args.timeout <= 300:
    raise SystemExit('--timeout must be between 1 and 300 seconds')

base = EXEC / f'{args.host}-compile-r1'
plan_path = base / f'plan-{args.phase}-v4.json'
archive = base / f'actual-{args.phase}-r1'
remote_root = f'D:/Claude/swiftright/.factory-work/hosts/{args.host}/{args.phase}-r1'
receipt_name = 'observation.json'
stream_names = ('compile.stdout.bin', 'compile.stderr.bin')

def require(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)

def regular(path: Path, cap: int):
    require(path.is_file() and not path.is_symlink(), f'bounded regular file required: {path}')
    require(path.stat().st_size <= cap, f'file cap exceeded: {path}')

def stream_hash(path: Path, cap: int) -> tuple[str, int]:
    regular(path, cap)
    digest = hashlib.sha256()
    total = 0
    with path.open('rb') as handle:
        while True:
            chunk = handle.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
            total += len(chunk)
    return digest.hexdigest(), total

def load_json(path: Path):
    regular(path, MAX_JSON)
    return json.loads(path.read_text(encoding='utf-8-sig'))

def unprefix(value) -> str:
    require(isinstance(value, str), 'hash field must be string')
    return value.removeprefix('sha256:').lower()

def fetch(remote_name: str, local: Path, cap: int):
    require(not local.exists(), f'refuse overwrite of archive member: {local}')
    # Remote source is assembled from fixed host/name components. No shell is
    # used, & no delete or mutation command is sent to Dell.
    remote = f'win:{remote_root}/{remote_name}'
    result = subprocess.run(['scp', '-q', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', remote, str(local)],
                            timeout=args.timeout, check=False)
    require(result.returncode == 0, f'SCP fetch failed for {remote_name}: {result.returncode}')
    regular(local, cap)

def fetch_absolute(remote_path: str, local: Path, cap: int):
    require(remote_path.startswith(f'D:/Claude/swiftright/.factory-work/hosts/{args.host}/package/'),
            'executable path escaped owned package root')
    require('..' not in Path(remote_path).parts, 'executable path traversal')
    require(not local.exists(), f'refuse overwrite of archive member: {local}')
    result = subprocess.run(['scp', '-q', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', f'win:{remote_path}', str(local)],
                            timeout=args.timeout, check=False)
    require(result.returncode == 0, f'SCP fetch failed for executable: {result.returncode}')
    regular(local, cap)

require(plan_path.is_file() and not plan_path.is_symlink(), f'final plan missing: {plan_path}')
require(not archive.exists(), f'refuse overwrite of existing final archive: {archive}')
plan_hash, plan_bytes = stream_hash(plan_path, MAX_JSON)
plan = load_json(plan_path)
require(plan.get('kind') == 'factory-pilot-five-compiler-plan-v1', 'final plan kind mismatch')
require(plan.get('phase') == args.phase, 'plan phase mismatch')
require(plan.get('executionEligible') is False, 'final receipt archive cannot change eligibility')
if args.phase == 'final':
    require(plan.get('expectedHostHash', '').startswith('sha256:'), 'final host hash missing')
else:
    require(plan.get('expectedHostHash') is None and plan.get('case') is None, 'prebuild final bindings present')
compile_request = plan.get('compileRequest') or {}
package_path = compile_request.get('packagePath')
scratch_path = compile_request.get('scratchPath')
require(isinstance(package_path, str) and isinstance(scratch_path, str), 'compile paths missing')
require(package_path == f'D:\\Claude\\swiftright\\.factory-work\\hosts\\{args.host}\\package',
        'final plan package host mismatch')
require(scratch_path.startswith(package_path + '\\'), 'final plan scratch escaped package')
expected_exe = scratch_path + r'\x86_64-unknown-windows-msvc\release\FactoryProbe.exe'

archive.mkdir()
try:
    fetch(receipt_name, archive / receipt_name, MAX_JSON)
    for name in stream_names:
        fetch(name, archive / name, MAX_STREAM)
    receipt = load_json(archive / receipt_name)
    require(receipt.get('kind') == 'factory-pilot-five-owned-compile-v1', 'final receipt kind mismatch')
    require(receipt.get('phase') == args.phase, 'receipt phase mismatch')
    require(receipt.get('host') in (None, args.host), 'final receipt host mismatch')
    require(receipt.get('planSha256', '').lower() == plan_hash, 'final receipt plan hash mismatch')
    require(receipt.get('case') == plan.get('case'), 'final receipt case binding mismatch')
    for field in ('exitCode', 'kernelWait', 'jobActiveCount', 'cleanupJobActive'):
        require(receipt.get(field) == 0, f'final receipt {field} must be zero')
    for field in ('ownedExited', 'streamDrainComplete', 'streamsSealed', 'originalHandleRetained'):
        require(receipt.get(field) is True, f'final receipt {field} must be true')
    for field in ('timedOut', 'outputCapExceeded', 'nativeActions'):
        require(receipt.get(field) in (False, 0), f'final receipt {field} indicates unsafe completion')
    require(receipt.get('exePath') == expected_exe, 'final receipt executable path mismatch')
    exe_remote = receipt['exePath'].replace('\\', '/')
    fetch_absolute(exe_remote, archive / 'FactoryProbe.exe', MAX_EXE)

    member_rows = []
    for name, cap in ((receipt_name, MAX_JSON), *[(n, MAX_STREAM) for n in stream_names], ('FactoryProbe.exe', MAX_EXE)):
        digest, size = stream_hash(archive / name, cap)
        member_rows.append({'path': name, 'bytes': size, 'sha256': digest})
    for stream in ('stdout', 'stderr'):
        row = next(item for item in member_rows if item['path'] == f'compile.{stream}.bin')
        require(receipt.get(f'{stream}Bytes') == row['bytes'], f'{stream} byte count mismatch')
        require(unprefix(receipt.get(f'{stream}Sha256')) == row['sha256'], f'{stream} hash mismatch')
    exe_row = next(item for item in member_rows if item['path'] == 'FactoryProbe.exe')
    require(receipt.get('exeBytes') == exe_row['bytes'], 'executable byte count mismatch')
    require(unprefix(receipt.get('exeSha256')) == exe_row['sha256'], 'executable hash mismatch')
    if args.phase == 'final':
        require(plan.get('expectedHostHash', '').lower() == 'sha256:' + exe_row['sha256'], 'expected host hash mismatch')
    manifest = {
        'kind': f'factory-pilot-five-{args.phase}-archive-v1',
        'host': args.host,
        'remoteRoot': remote_root,
        'plan': {'path': str(plan_path.relative_to(ROOT)), 'bytes': plan_bytes, 'sha256': plan_hash},
        'members': member_rows,
        'receiptChecks': {
            'planHash': True, 'originalHandleRetained': True, 'kernelWait': 0,
            'jobActiveCount': 0, 'cleanupJobActive': 0, 'streamsSealed': True,
            'streamDrainComplete': True, 'nativeActions': 0,
        },
        'qualified': False,
    }
    manifest_path = archive / 'archive-manifest.json'
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps({'host': args.host, 'archive': str(archive), 'members': len(member_rows), 'qualified': False}))
except Exception:
    # Preserve fetched evidence for root diagnosis; never delete remote or local
    # bytes from this helper.
    raise
