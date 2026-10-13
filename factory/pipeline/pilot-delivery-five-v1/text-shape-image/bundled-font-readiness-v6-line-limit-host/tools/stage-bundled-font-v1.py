"""Stage exact Tinos host & DirectWrite paint-canary inputs for root execution.

Default mode performs bounded local source admission only. ``--remote`` copies
that immutable stage to Windows & records a read-only preflight request.
``--remote --run-canary`` invokes pinned root transport for positive & negative
paint canaries; compiler, Job Object supervision, & capture remain root-owned.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path('/Volumes/D/claude/swiftright')
PACKET = ROOT / 'factory/pipeline/pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v6-line-limit-host'
HOST = PACKET
PACKAGE = HOST / 'package'
PAINT_CANARY = PACKET / 'paint-canary-source/paint-canary.patch'
PAINT_CANARY_README = PACKET / 'paint-canary-source/README.md'
DISCOVERY = ROOT / 'factory/pipeline/pilot-delivery-five-v1/root-execution/system-image-tools-actual-r1/transport.json.stdout.bin'
DEFAULT_STAGE = ROOT / '.factory-work/hosts/bundled-font-readiness-v6-line-limit-host/windows-host-inputs-r1'
REMOTE_REPO = r'D:/Claude/swiftright'
PINNED_RUNNER = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root/run_pinned_windows_v1.py')
MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_LOG = 8 * 1024 * 1024
FONT_SHA = '60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61'
FONT_BYTES = 521588

parser = argparse.ArgumentParser()
parser.add_argument('--discovery-stdout', type=Path, default=DISCOVERY)
parser.add_argument('--stage', type=Path, default=None)
parser.add_argument('--remote', action='store_true')
parser.add_argument('--run-canary', action='store_true')
parser.add_argument('--revision', type=int, default=1)
parser.add_argument('--host', default='win')
parser.add_argument('--timeout', type=int, default=300)
parser.add_argument('--vctip-path')
parser.add_argument('--vctip-sha256')
args = parser.parse_args()
if not 1 <= args.revision <= 10:
    raise SystemExit('--revision must be between 1 and 10')
if args.stage is None:
    args.stage = ROOT / f'.factory-work/hosts/bundled-font-readiness-v6-line-limit-host/windows-host-inputs-r{args.revision}'
REMOTE_INPUT = rf'D:/Claude/swiftright/.factory-work/hosts/bundled-font-readiness-v6-line-limit-host/windows-host-inputs-r{args.revision}'
REMOTE_OUTPUT = rf'D:/Claude/swiftright/.factory-work/hosts/bundled-font-readiness-v6-line-limit-host/paint-canary-r{args.revision}'
if args.run_canary and not args.remote:
    raise SystemExit('--run-canary requires --remote')
if args.run_canary:
    raise SystemExit('v6 packet contains paint-canary.patch only; no canary executable/source is assumed')
if not 30 <= args.timeout <= 1800:
    raise SystemExit('--timeout must be between 30 and 1800')
if bool(args.vctip_path) != bool(args.vctip_sha256):
    raise SystemExit('--vctip-path & --vctip-sha256 must be supplied together')
if args.vctip_sha256 and (len(args.vctip_sha256) != 64 or any(c not in '0123456789abcdefABCDEF' for c in args.vctip_sha256)):
    raise SystemExit('--vctip-sha256 must be 64 hex characters')


def require(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)


def regular(path: Path, cap: int):
    require(path.is_file() and not path.is_symlink(), f'bounded regular file required: {path}')
    require(path.stat().st_size <= cap, f'file cap exceeded: {path}')


def digest(path: Path, cap: int = MAX_FILE) -> tuple[str, int]:
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


def copy_bounded(source: Path, target: Path, cap: int = MAX_FILE):
    regular(source, cap)
    require(not target.exists(), f'refuse overwrite: {target}')
    target.parent.mkdir(parents=True, exist_ok=True)
    with source.open('rb') as src, target.open('xb') as dst:
        shutil.copyfileobj(src, dst, 1024 * 1024)


def load_inventory():
    inventory = load_json(args.discovery_stdout)
    require(inventory.get('kind') == 'factory-system-image-measured-tool-inventory-v1', 'discovery kind mismatch')
    require(inventory.get('nativeActions') == 0 and inventory.get('compilerActions') == 0 and inventory.get('deletionActions') == 0,
            'discovery had forbidden actions')
    expected = {
        'compiler': ('C:\\Program Files\\Microsoft Visual Studio\\18\\Community\\VC\\Tools\\MSVC\\14.51.36231\\bin\\Hostx64\\x64\\cl.exe', 893328, 'dc8426b8760d92cf757df3d10b9f0244a95b454ff43194a58161568a0ec70d53'),
        'vcvars64': ('C:\\Program Files\\Microsoft Visual Studio\\18\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat', 39, '6b516d8fcf543c14b2d861e1f45661e0029230fe0dc48e86ce78522801822209'),
        'font': ('C:\\Windows\\Fonts\\SegoeIcons.ttf', 471716, 'af496bd8ed18e8b45ea9c914bb3319204ab4fac450e0f4d3aab62bac6c02e5e9'),
    }
    for key, (path, size, sha) in expected.items():
        row = inventory.get(key) or {}
        require(row.get('path') == path and row.get('bytes') == size and row.get('sha256') == sha,
                f'discovery {key} mismatch')
    return inventory


def stage_sources(inventory):
    require(not args.stage.exists(), f'refuse overwrite existing stage: {args.stage}')
    package_manifest = load_json(HOST / 'source-manifest.json')
    require(package_manifest.get('sourceHash') == 'sha256:e3917a212ec66304bac8631b835b05f95956bff695b13688743b967b522cfadb',
            'host source manifest identity mismatch')
    rows = []
    package_plan = load_json(PACKAGE / 'plan.json')
    require(package_plan.get('runtimeSourceCommit') == '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b', 'host runtime pin mismatch')
    require(package_plan.get('rendererSha256') == 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93', 'host renderer pin mismatch')
    require(package_plan.get('bridgeSourceCommit') == '0a745ab', 'host bridge pin mismatch')
    package_entries = list(package_manifest.get('files', []))
    package_entries.append({'path': 'plan.json', 'sha256': None, 'bytes': None})
    for entry in package_entries:
        relative = entry['path']
        source = PACKAGE / relative
        if not source.is_file():
            source = HOST / relative
        copied = args.stage / 'package' / relative
        copy_bounded(source, copied)
        sha, size = digest(copied)
        if entry['sha256'] is not None:
            require(sha == entry['sha256'].removeprefix('sha256:') and size == entry['bytes'], f'package source drift: {relative}')
        rows.append({'path': f'package/{relative}', 'bytes': size, 'sha256': sha, 'origin': 'windows-host/source-manifest.json'})
    for source, relative in ((PAINT_CANARY, 'package/paint-canary.patch'), (PAINT_CANARY_README, 'paint-canary-source/README.md')):
        copied = args.stage / relative
        copy_bounded(source, copied)
        sha, size = digest(copied)
        rows.append({'path': relative, 'bytes': size, 'sha256': sha, 'origin': str(source.relative_to(ROOT))})
    for source, relative in ((HOST / 'tools/stage-tinos-font.ps1', 'tools/stage-tinos-font.ps1'),):
        copied = args.stage / relative
        copy_bounded(source, copied)
        sha, size = digest(copied)
        rows.append({'path': relative, 'bytes': size, 'sha256': sha, 'origin': str(source.relative_to(ROOT))})
    resource = args.stage / 'package/Resources/Tinos-Regular.ttf'
    sha, size = digest(resource)
    require(sha == FONT_SHA and size == FONT_BYTES, 'staged Tinos resource mismatch')
    request = {
        'kind': 'factory-bundled-font-windows-remote-request-v1',
        'remoteHost': args.host,
        'remoteInput': REMOTE_INPUT,
        'repo': REMOTE_REPO,
        'packagePath': REMOTE_INPUT + r'/package',
        'paintCanaryPatchPath': REMOTE_INPUT + r'/package/paint-canary.patch',
        'paintCanarySource': None,
        'fontPath': REMOTE_INPUT + r'/package/Resources/Tinos-Regular.ttf',
        'fontSha256': 'sha256:' + FONT_SHA,
        'compilerPath': inventory['compiler']['path'],
        'vcVars64Path': inventory['vcvars64']['path'],
        'vctipPath': args.vctip_path,
        'vctipSha256': ('sha256:' + args.vctip_sha256 if args.vctip_sha256 else None),
        'swiftPath': json.loads((PACKAGE / 'plan.json').read_text(encoding='utf-8'))['compileRequest']['compilerPath'],
        'swiftPathMeasured': False,
        'compile': {
            'canaryArgv': None,
            'swiftArgv': ['swift.exe', 'build', '--build-system', 'native', '-v', '--package-path', REMOTE_INPUT + r'/package', '--scratch-path', REMOTE_INPUT + r'/package/build-tinos-r3/scratch', '--jobs', '1', '-Xswiftc', '-j1', '-Xswiftc', '-num-threads', '-Xswiftc', '1', '-c', 'release'],
            'nativeProductPath': REMOTE_INPUT + r'/package/build-tinos-r3/scratch/x86_64-unknown-windows-msvc/release/FactoryProbe.exe',
            'swiftCompilerMustBeMeasuredBeforeStart': True,
        },
        'canary': {'status': 'patch-only-not-runnable', 'patchPath': REMOTE_INPUT + r'/package/paint-canary.patch', 'sourcePath': None, 'executablePath': None, 'rendererSelection': 'unproven'},
        'rootPinnedInvocation': {
            'runner': str(PINNED_RUNNER),
            'argv': ['python3', str(PINNED_RUNNER), '--compiler-budget', '--deadline', str(args.timeout)],
            'requirements': ['preflight measured cl/vcvars/font before compile', '1GiB Job Object', 'jobs=1', 'sealed stdout/stderr before quiescence decision', 'original process handle retained', 'active process count=0', 'stage exact Tinos resource adjacent to executable before host launch'],
        },
        'canaryOutputChecks': {'status': 'patch-only-not-runnable', 'patchSha256': 'sha256:59f05a177b557559024604d668f633206efa147f99e4223acc76ea4e4a126765'},
        'launch': {
            'resourceStageScript': REMOTE_INPUT + r'/tools/stage-tinos-font.ps1',
            'args': ['--tinos-font', REMOTE_INPUT + r'/package/Resources/Tinos-Regular.ttf'],
            'rendererPath': REMOTE_REPO + r'/.factory-work/inputs/renderer/swiftright_render.dll',
            'bridgePackagePath': REMOTE_REPO + r'/.factory-work/inputs/SwiftRightBridge',
            'runtimePackagePath': REMOTE_REPO + r'/.factory-work/runtime-stage/runtime',
        },
        'supervision': {'owner': 'root', 'memoryCapBytes': 1073741824, 'jobs': 1, 'frontendJobs': 1, 'frontendThreads': 1, 'nativeActions': 0, 'remoteDeletion': False},
        'requiredChannels': ['compile/source join', 'resource hash', 'canary provider paint', 'ABI bridge measurement', 'native text run/glyph paint', 'screenshot', 'UIA'],
        'qualification': 'observational until root proves renderer/provider selection',
    }
    manifest = {
        'kind': 'factory-bundled-font-windows-input-stage-v1',
        'stage': str(args.stage), 'remoteInput': REMOTE_INPUT, 'sourceRows': rows,
        'packageSourceManifestSha256': package_manifest['sourceHash'],
        'font': {'path': 'package/Resources/Tinos-Regular.ttf', 'bytes': FONT_BYTES, 'sha256': 'sha256:' + FONT_SHA},
        'discovery': inventory, 'memoryCapBytes': 1073741824, 'jobs': 1,
        'frontendJobs': 1, 'frontendThreads': 1, 'nativeActions': 0, 'remoteDeletion': False,
    }
    (args.stage / 'input-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (args.stage / 'remote-request.json').write_text(json.dumps(request, indent=2) + '\n', encoding='utf-8')
    return manifest, request


def load_stage():
    manifest = load_json(args.stage / 'input-manifest.json')
    request = load_json(args.stage / 'remote-request.json')
    require(manifest.get('kind') == 'factory-bundled-font-windows-input-stage-v1', 'stage manifest kind mismatch')
    require(request.get('kind') == 'factory-bundled-font-windows-remote-request-v1', 'remote request kind mismatch')
    for row in manifest.get('sourceRows', []):
        sha, size = digest(args.stage / row['path'])
        require(sha == row['sha256'] and size == row['bytes'], f'staged source drift: {row["path"]}')
    sha, size = digest(args.stage / 'package/Resources/Tinos-Regular.ttf')
    require(sha == FONT_SHA and size == FONT_BYTES, 'staged resource drift')
    patch_sha, patch_size = digest(args.stage / 'package/paint-canary.patch')
    require(patch_sha == '59f05a177b557559024604d668f633206efa147f99e4223acc76ea4e4a126765' and patch_size == 5638, 'staged paint-canary patch drift')
    return manifest, request


def run_capture(argv: list[str], stdout: Path, stderr: Path):
    require(not stdout.exists() and not stderr.exists(), 'refuse overwrite transport streams')
    stdout.parent.mkdir(parents=True, exist_ok=True)
    started = time.time()
    with stdout.open('xb') as out, stderr.open('xb') as err:
        process = subprocess.Popen(argv, stdout=out, stderr=err)
        code = process.wait(timeout=args.timeout)
    out_hash, out_bytes = digest(stdout, MAX_LOG)
    err_hash, err_bytes = digest(stderr, MAX_LOG)
    return {'argv': argv, 'exitCode': code, 'elapsedSeconds': round(time.time() - started, 3),
            'stdout': {'path': str(stdout.relative_to(ROOT)), 'bytes': out_bytes, 'sha256': out_hash},
            'stderr': {'path': str(stderr.relative_to(ROOT)), 'bytes': err_bytes, 'sha256': err_hash}}


def remote_powershell(args_: list[str]) -> str:
    def quote(value: str) -> str:
        return '"' + value.replace('"', '\\"') + '"' if any(ch.isspace() for ch in value) or '"' in value else value
    return 'powershell.exe ' + ' '.join(quote(value) for value in args_)


def transport(manifest, request):
    transport_dir = args.stage / 'transport'
    require(not transport_dir.exists(), f'refuse overwrite transport directory: {transport_dir}')
    transport_dir.mkdir()
    remote_stage = REMOTE_INPUT.replace('/', '\\')
    parents = {str(Path(row['path']).parent).replace('/', '\\') for row in manifest['sourceRows']}
    parents.discard('.')
    mkdir_parts = [f"New-Item -ItemType Directory -Force -Path '{remote_stage}\\{parent}' | Out-Null" for parent in sorted(parents)]
    mkdir = '; '.join(mkdir_parts)
    records = [run_capture(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', args.host, 'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', mkdir], transport_dir / 'mkdir.stdout.bin', transport_dir / 'mkdir.stderr.bin')]
    require(records[-1]['exitCode'] == 0, 'remote input directory creation failed')
    for row in manifest['sourceRows']:
        local = args.stage / row['path']
        remote = 'win:' + REMOTE_INPUT + '/' + row['path']
        records.append(run_capture(['scp', '-q', str(local), remote], transport_dir / ('scp-' + row['path'].replace('/', '_') + '.stdout.bin'), transport_dir / ('scp-' + row['path'].replace('/', '_') + '.stderr.bin')))
        require(records[-1]['exitCode'] == 0, f'SCP failed: {row["path"]}')
    request_path = args.stage / 'remote-request.json'
    records.append(run_capture(['scp', '-q', str(request_path), 'win:' + REMOTE_INPUT + '/remote-request.json'], transport_dir / 'scp-request.stdout.bin', transport_dir / 'scp-request.stderr.bin'))
    require(records[-1]['exitCode'] == 0, 'SCP failed: remote request')
    preflight = """$ErrorActionPreference='Stop'; $root='__ROOT__'; if(-not (Test-Path -LiteralPath (Join-Path $root 'package\\Package.swift'))){throw 'package missing'}; if((Get-Item -LiteralPath (Join-Path $root 'package\\Resources\\Tinos-Regular.ttf')).Length -ne 521588){throw 'resource size mismatch'}; $h=(Get-FileHash -LiteralPath (Join-Path $root 'package\\Resources\\Tinos-Regular.ttf') -Algorithm SHA256).Hash.ToLowerInvariant(); if($h -ne '60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61'){throw 'resource hash mismatch'}; $p=Join-Path $root 'package\\paint-canary.patch'; if((Get-Item -LiteralPath $p).Length -ne 5638){throw 'paint-canary patch size mismatch'}; $ph=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant(); if($ph -ne '59f05a177b557559024604d668f633206efa147f99e4223acc76ea4e4a126765'){throw 'paint-canary patch hash mismatch'}; [ordered]@{kind='factory-bundled-font-stage-preflight-v1';status='passed';compilerStarted=$false;nativeActions=0;remoteDeletion=$false;canary='patch-only-not-runnable'}|ConvertTo-Json -Compress""".replace('__ROOT__', REMOTE_INPUT.replace('/', '\\'))
    records.append(run_capture(['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8', args.host, 'powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', preflight], transport_dir / 'preflight.stdout.bin', transport_dir / 'preflight.stderr.bin'))
    require(records[-1]['exitCode'] == 0, 'remote stage preflight failed')
    require(not args.run_canary, 'v6 packet carries patch only; no canary executable/source is assumed')
    result = {'kind': 'factory-bundled-font-windows-transport-v1', 'host': args.host, 'records': records, 'nativeActions': 0, 'remoteDeletion': False, 'execution': 'root-owned-supervisor-required'}
    (transport_dir / 'transport-manifest.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    return result


inventory = load_inventory()
if args.stage.exists():
    require(args.remote, 'existing stage requires --remote; local staging is fail-closed')
    manifest, request = load_stage()
else:
    manifest, request = stage_sources(inventory)
result = {'kind': 'factory-bundled-font-windows-stage-v1', 'stage': str(args.stage), 'remote': args.remote,
          'manifest': manifest, 'request': request, 'nativeActions': 0, 'remoteDeletion': False}
if args.remote:
    result['transport'] = transport(manifest, request)
print(json.dumps(result, indent=2))
