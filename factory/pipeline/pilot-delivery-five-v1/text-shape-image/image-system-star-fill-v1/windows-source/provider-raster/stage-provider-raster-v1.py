"""Stage & optionally transport exact star.fill DirectWrite producer inputs.

Default mode is local source admission only. --remote --run is root-owned and
uses SSH/SCP without remote deletion; producer PowerShell owns compiler/producer
Job Objects, 1 GiB caps, timeout, stream caps, & receipt checks.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path('/Volumes/D/claude/swiftright')
PACKET = ROOT / 'factory/pipeline/pilot-delivery-five-v1/text-shape-image/image-system-star-fill-v1/windows-source/provider-raster'
DISCOVERY = ROOT / 'factory/pipeline/pilot-delivery-five-v1/root-execution/system-image-tools-actual-r1/transport.json.stdout.bin'
MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_LOG = 8 * 1024 * 1024
PINNED_RUNNER = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root/run_pinned_windows_v1.py')
REMOTE_INPUT_BASE = r'D:/Claude/swiftright/.factory-work/hosts/system-star-fill/provider-raster-inputs-r1'
REMOTE_OUTPUT_BASE = r'D:/Claude/swiftright/.factory-work/hosts/system-star-fill/provider-raster-r1'
REMOTE_REPO = r'D:/Claude/swiftright'

parser = argparse.ArgumentParser()
parser.add_argument('--discovery-stdout', type=Path, default=DISCOVERY)
parser.add_argument('--stage', type=Path, default=ROOT / '.factory-work/hosts/system-star-fill/provider-raster-inputs-r1')
parser.add_argument('--remote', action='store_true')
parser.add_argument('--run', action='store_true')
parser.add_argument('--host', default='win')
parser.add_argument('--timeout', type=int, default=900)
parser.add_argument('--revision', type=int, choices=range(1, 11), default=1)
parser.add_argument('--vctip-path')
parser.add_argument('--vctip-sha256')
args = parser.parse_args()
if args.run and not args.remote:
    raise SystemExit('--run requires --remote')
if not 30 <= args.timeout <= 1800:
    raise SystemExit('--timeout must be between 30 and 1800')
if bool(args.vctip_path) != bool(args.vctip_sha256):
    raise SystemExit('--vctip-path & --vctip-sha256 must be supplied together')
if args.vctip_sha256 and (len(args.vctip_sha256) != 64 or any(c not in '0123456789abcdefABCDEF' for c in args.vctip_sha256)):
    raise SystemExit('--vctip-sha256 must be 64 hex characters')
DEFAULT_STAGE_BASE = ROOT / '.factory-work/hosts/system-star-fill/provider-raster-inputs-r1'
if args.stage == DEFAULT_STAGE_BASE and args.revision != 1:
    args.stage = DEFAULT_STAGE_BASE.with_name(f'provider-raster-inputs-r{args.revision}')
REMOTE_INPUT = REMOTE_INPUT_BASE.replace('inputs-r1', f'inputs-r{args.revision}')
REMOTE_OUTPUT = REMOTE_OUTPUT_BASE.replace('raster-r1', f'raster-r{args.revision}')


def require(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)


def regular(path: Path, cap: int):
    require(path.is_file() and not path.is_symlink(), f'bounded regular file required: {path}')
    require(path.stat().st_size <= cap, f'file cap exceeded: {path}')


def digest(path: Path, cap: int) -> tuple[str, int]:
    regular(path, cap)
    h = hashlib.sha256()
    total = 0
    with path.open('rb') as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
            total += len(chunk)
    return h.hexdigest(), total


def load_json(path: Path):
    regular(path, MAX_JSON)
    return json.loads(path.read_text(encoding='utf-8-sig'))


def copy_bounded(source: Path, target: Path, cap: int):
    regular(source, cap)
    require(not target.exists(), f'refuse overwrite: {target}')
    target.parent.mkdir(parents=True, exist_ok=True)
    with source.open('rb') as src, target.open('xb') as dst:
        shutil.copyfileobj(src, dst, 1024 * 1024)
    regular(target, cap)


def run_capture(argv: list[str], stdout: Path, stderr: Path, timeout: int):
    require(not stdout.exists() and not stderr.exists(), 'refuse overwrite transport streams')
    stdout.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with stdout.open('xb') as out, stderr.open('xb') as err:
        process = subprocess.Popen(argv, stdout=out, stderr=err)
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)
            raise RuntimeError(f'transport timeout: {argv[0]}')
    out_hash, out_bytes = digest(stdout, MAX_LOG)
    err_hash, err_bytes = digest(stderr, MAX_LOG)
    return {'argv': argv, 'exitCode': code, 'elapsedSeconds': round(time.time() - started, 3),
            'stdout': {'path': str(stdout.relative_to(ROOT)), 'bytes': out_bytes, 'sha256': out_hash},
            'stderr': {'path': str(stderr.relative_to(ROOT)), 'bytes': err_bytes, 'sha256': err_hash}}


def load_inventory():
    inventory = json.loads(args.discovery_stdout.read_text(encoding='utf-8-sig'))
    require(inventory.get('kind') == 'factory-system-image-measured-tool-inventory-v1', 'discovery kind mismatch')
    require(inventory.get('nativeActions') == 0 and inventory.get('compilerActions') == 0 and inventory.get('deletionActions') == 0, 'discovery had forbidden actions')
    expected = {
        'compiler': (r'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64\cl.exe', 893328, 'dc8426b8760d92cf757df3d10b9f0244a95b454ff43194a58161568a0ec70d53'),
        'vcvars64': (r'C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat', 39, '6b516d8fcf543c14b2d861e1f45661e0029230fe0dc48e86ce78522801822209'),
        'font': (r'C:\Windows\Fonts\SegoeIcons.ttf', 471716, 'af496bd8ed18e8b45ea9c914bb3319204ab4fac450e0f4d3aab62bac6c02e5e9'),
    }
    # Correct the deliberately split font digest while retaining exact discovered values.
    expected['font'] = ('C:\\Windows\\Fonts\\SegoeIcons.ttf', 471716, 'af496bd8ed18e8b45ea9c914bb3319204ab4fac450e0f4d3aab62bac6c02e5e9')
    for key, (path, size, sha) in expected.items():
        row = inventory.get(key) or {}
        require(row.get('path') == path and row.get('bytes') == size and row.get('sha256') == sha, f'discovery {key} mismatch')
    return inventory


def remote_powershell(command_args: list[str]) -> str:
    def quote(value: str) -> str:
        if any(ch.isspace() for ch in value) or '"' in value:
            return '"' + value.replace('"', '\\"') + '"'
        return value
    return 'powershell.exe ' + ' '.join(quote(value) for value in command_args)


def stage_sources(inventory):
    require(not args.stage.exists(), f'refuse overwrite existing stage: {args.stage}')
    files = [
        'GlyphRasterProducer.cpp', 'ProviderOwnedJobProcess.cs',
        'produce-provider-raster-v1.ps1', 'producer-plan.json', 'README.md',
    ]
    rows = []
    for name in files:
        source = PACKET / name
        target = args.stage / 'provider-raster' / name
        copy_bounded(source, target, MAX_FILE)
        sha, size = digest(target, MAX_FILE)
        rows.append({'path': f'provider-raster/{name}', 'bytes': size, 'sha256': sha})
    manifest = {
        'kind': 'factory-system-image-provider-raster-input-stage-v1',
        'stage': str(args.stage), 'remoteInput': REMOTE_INPUT, 'remoteOutput': REMOTE_OUTPUT,
        'sourceRows': rows, 'discovery': inventory, 'memoryCapBytes': 1073741824,
        'compilerJobs': 1, 'timeoutSeconds': args.timeout, 'innerDeadlineSeconds': 120, 'streamCapBytes': MAX_LOG,
        'remoteDeletion': False, 'nativeActions': 0,
    }
    (args.stage / 'input-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    remote_script = REMOTE_INPUT + r'\provider-raster\produce-provider-raster-v1.ps1'
    request = {
        'kind': 'factory-system-image-provider-raster-remote-request-v1',
        'remoteHost': args.host, 'remoteInput': REMOTE_INPUT, 'remoteOutput': REMOTE_OUTPUT,
        'script': remote_script, 'repo': REMOTE_REPO,
        'compilerPath': inventory['compiler']['path'], 'vcVars64Path': inventory['vcvars64']['path'],
        'vctipPath': args.vctip_path, 'vctipSha256': ('sha256:' + args.vctip_sha256 if args.vctip_sha256 else None),
        'fontPath': inventory['font']['path'], 'fontSha256': 'sha256:' + inventory['font']['sha256'],
        'sourceRows': rows, 'preflight': True, 'runRequiresRootOwnedTransport': True,
        'remoteDeletion': False, 'memoryCapBytes': 1073741824, 'jobs': 1,
        'vctipSupervision': {'pinnedPath': args.vctip_path, 'pinnedSha256': args.vctip_sha256, 'streamsSealedBeforeDecision': True, 'foreignDescendantAccepted': False, 'ambiguousDescendantAccepted': False},
        'faultControl': {'argument': '-FaultMode empty-coverage', 'expectedExitCode': 'nonzero', 'expectedError': 'empty-coverage', 'mustUseFreshOutputRoot': True},
    }
    (args.stage / 'remote-request.json').write_text(json.dumps(request, indent=2) + '\n', encoding='utf-8')
    return manifest, request



def load_stage():
    manifest = load_json(args.stage / 'input-manifest.json')
    request = load_json(args.stage / 'remote-request.json')
    require(manifest.get('kind') == 'factory-system-image-provider-raster-input-stage-v1', 'stage manifest kind mismatch')
    require(request.get('kind') == 'factory-system-image-provider-raster-remote-request-v1', 'remote request kind mismatch')
    for row in manifest.get('sourceRows', []):
        path = args.stage / row['path']
        sha, size = digest(path, MAX_FILE)
        require(sha == row['sha256'] and size == row['bytes'], f'staged source drift: {row["path"]}')
    return manifest, request

def transport(manifest, request):
    transport_dir = args.stage / 'transport'
    require(not transport_dir.exists(), f'refuse overwrite transport directory: {transport_dir}')
    transport_dir.mkdir()
    mkdir_script = "New-Item -ItemType Directory -Force -Path '" + REMOTE_INPUT.replace('/', '\\') + "\\provider-raster' | Out-Null"
    records = [run_capture(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', args.host, 'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', mkdir_script], transport_dir / 'mkdir.stdout.bin', transport_dir / 'mkdir.stderr.bin', 30)]
    require(records[-1]['exitCode'] == 0, 'remote input directory creation failed')
    for row in manifest['sourceRows']:
        local = args.stage / row['path']
        remote = 'win:' + REMOTE_INPUT.replace('D:', 'D:').replace('\\', '/') + '/' + row['path'].replace('\\', '/')
        records.append(run_capture(['scp', '-q', str(local), remote], transport_dir / (Path(row['path']).stem + '.scp.stdout.bin'), transport_dir / (Path(row['path']).stem + '.scp.stderr.bin'), 120))
        require(records[-1]['exitCode'] == 0, f'SCP failed: {row["path"]}')
    vctip_args = (['-VctipPath', args.vctip_path, '-VctipSha256', args.vctip_sha256] if args.vctip_path else [])
    preflight_args = ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', request['script'], '-CompilerPath', request['compilerPath'], '-VcVars64Path', request['vcVars64Path'], '-FontPath', request['fontPath'], '-Repo', request['repo'], '-Revision', str(args.revision)] + vctip_args + ['-PreflightOnly']
    records.append(run_capture(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', args.host, remote_powershell(preflight_args)], transport_dir / 'preflight.stdout.bin', transport_dir / 'preflight.stderr.bin', 120))
    require(records[-1]['exitCode'] == 0, 'remote provider preflight failed')
    if args.run:
        remote_script_path = rf'D:\Claude\swiftright\.factory-work\hosts\system-star-fill\run-provider-r{args.revision}.ps1'
        remote_receipt_path = rf'D:\Claude\swiftright\.factory-work\hosts\system-star-fill\run-provider-r{args.revision}-transport.json'
        root_script = transport_dir / f'run-provider-r{args.revision}.ps1'
        require(not root_script.exists(), f'refuse overwrite root runner: {root_script}')
        script = """$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$inputRoot='__INPUT_ROOT__'
$runner=Join-Path $inputRoot 'provider-raster\\produce-provider-raster-v1.ps1'
& $runner -CompilerPath 'C:\\Program Files\\Microsoft Visual Studio\\18\\Community\\VC\\Tools\\MSVC\\14.51.36231\\bin\\Hostx64\\x64\\cl.exe' -VcVars64Path 'C:\\Program Files\\Microsoft Visual Studio\\18\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat' -FontPath 'C:\\Windows\\Fonts\\SegoeIcons.ttf' -Repo 'D:\\Claude\\swiftright' -Revision __REV__ -InnerDeadlineSeconds 120 __VCTIP__ -PreflightOnly
& $runner -CompilerPath 'C:\\Program Files\\Microsoft Visual Studio\\18\\Community\\VC\\Tools\\MSVC\\14.51.36231\\bin\\Hostx64\\x64\\cl.exe' -VcVars64Path 'C:\\Program Files\\Microsoft Visual Studio\\18\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat' -FontPath 'C:\\Windows\\Fonts\\SegoeIcons.ttf' -Repo 'D:\\Claude\\swiftright' -Revision __REV__ -InnerDeadlineSeconds 120 __VCTIP__
$output='__OUTPUT_ROOT__'
if(-not (Test-Path -LiteralPath (Join-Path $output 'provider-raster-manifest.json'))){throw 'producer manifest absent'}
Get-Content -LiteralPath (Join-Path $output 'provider-raster-manifest.json') -Raw
""".replace('__INPUT_ROOT__', REMOTE_INPUT.replace('/', '\\')).replace('__OUTPUT_ROOT__', REMOTE_OUTPUT.replace('/', '\\')).replace('__REV__', str(args.revision)).replace('__VCTIP__', ("-VctipPath '" + args.vctip_path + "' -VctipSha256 '" + args.vctip_sha256 + "'" if args.vctip_path else ''))
        root_script.write_text(script, encoding='utf-8')
        helper_stdout = transport_dir / 'pinned-run.stdout.bin'
        helper_stderr = transport_dir / 'pinned-run.stderr.bin'
        records.append(run_capture(['python3', str(PINNED_RUNNER), '--script', str(root_script), '--remote-script', remote_script_path, '--remote-receipt', remote_receipt_path, '--archive', str(transport_dir / 'pinned-run-archive'), '--deadline', str(args.timeout), '--compiler-budget'], helper_stdout, helper_stderr, args.timeout + 120))
        require(records[-1]['exitCode'] == 0, 'pinned provider run failed')
        archive_outputs(transport_dir, records)
    transport_manifest = {'kind': 'factory-system-image-provider-raster-transport-v1', 'host': args.host, 'records': records, 'remoteDeletion': False, 'nativeActions': 0, 'runSupervisor': str(PINNED_RUNNER) if args.run else None}
    (transport_dir / 'transport-manifest.json').write_text(json.dumps(transport_manifest, indent=2) + '\n', encoding='utf-8')
    return transport_manifest


def archive_outputs(transport_dir: Path, records):
    archive = args.stage / 'archive'
    require(not archive.exists(), f'refuse overwrite archive: {archive}')
    archive.mkdir()
    names = ['provider-raster-manifest.json', 'FactorySystemImageAssets.json', 'compile-observation.json', 'producer-observation.json', 'compile.stdout.bin', 'compile.stderr.bin', 'producer.stdout.bin', 'producer.stderr.bin', 'compiler/GlyphRasterProducer.exe', 'producer/star-fill.rgba.bin', 'producer/provider-metadata.json']
    for name in names:
        target = archive / name
        target.parent.mkdir(parents=True, exist_ok=True)
        remote = 'win:' + REMOTE_OUTPUT.replace('D:', 'D:').replace('\\', '/') + '/' + name.replace('\\', '/')
        result = run_capture(['scp', '-q', remote, str(target)], transport_dir / ('archive-' + name.replace('/', '_') + '.stdout.bin'), transport_dir / ('archive-' + name.replace('/', '_') + '.stderr.bin'), 180)
        require(result['exitCode'] == 0, f'archive SCP failed: {name}')
    manifest = load_json(archive / 'provider-raster-manifest.json')
    require(manifest.get('nativeActions') == 0 and manifest.get('memoryCapBytes') == 1073741824, 'provider manifest safety mismatch')
    for receipt_name in ('compile-observation.json', 'producer-observation.json'):
        receipt = load_json(archive / receipt_name)
        for field in ('ownedExited', 'originalHandleRetained', 'streamDrainComplete', 'streamsSealed'):
            require(receipt.get(field) is True, f'{receipt_name} {field} mismatch')
        require('ownedHelperStopped' in receipt, f'{receipt_name} helper-stop field missing')
        require(receipt.get('jobActiveCount') == 0 and receipt.get('cleanupJobActive') == 0, f'{receipt_name} job not quiescent')
    metadata = load_json(archive / 'producer/provider-metadata.json')
    require(metadata.get('identity') == 'star.fill' and metadata.get('unicode') == 'E735' and int(metadata.get('nonZeroAlphaPixels', 0)) > 0, 'positive raster coverage receipt mismatch')
    image_map = load_json(archive / 'FactorySystemImageAssets.json')
    require(image_map.get('identity') == 'star.fill' and image_map.get('status') == 'provider-raster-ready', 'provider map identity/status mismatch')
    require(image_map.get('rgbaSha256') == metadata.get('rgbaSha256'), 'provider map/raw metadata hash mismatch')
    (archive / 'archive-verification.json').write_text(json.dumps({'kind': 'factory-system-image-provider-raster-archive-verification-v1', 'manifest': manifest, 'remoteDeletion': False, 'nativeActions': 0}, indent=2) + '\n', encoding='utf-8')


inventory = load_inventory()
if args.stage.exists():
    require(args.remote, 'existing stage requires --remote; local staging is fail-closed')
    manifest, request = load_stage()
else:
    manifest, request = stage_sources(inventory)
result = {'kind': 'factory-system-image-provider-raster-stage-v1', 'stage': str(args.stage), 'remote': args.remote, 'run': args.run, 'manifest': manifest, 'request': request, 'nativeActions': 0}
if args.remote:
    result['transport'] = transport(manifest, request)
print(json.dumps(result, indent=2))
