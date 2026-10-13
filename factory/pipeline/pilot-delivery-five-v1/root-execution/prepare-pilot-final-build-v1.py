"""Validate one native prebuild & emit strict final-build source requests.

This source-only finalizer never launches compilation or capture. Root owns both.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys

ROOT = Path('/Volumes/D/claude/swiftright')
EXEC = ROOT / 'factory/pipeline/pilot-delivery-five-v1/root-execution'
PACKETS = {
    'image': 'text-shape-image/image-host-package-v1',
    'image-v2': 'text-shape-image/image-host-package-v2',
    'image-star-provider': 'text-shape-image/image-system-star-fill-v1/windows-source/provider-bound-delivery-v2',
    'image-star-observation': 'text-shape-image/image-system-star-fill-v9',
    'stack-overlay-colors': 'stack-layout/stack-overlay-centered-execution-v7',
    'custom-layout-colors': 'stack-layout/custom-layout-host-v2/direct-original-execution-v7',
    'rounded-stroke-boundary': 'text-shape-image/rounded-stroke-host-v1/continuous-observation-delivery-v5',
    'bundled-font-compiled': 'text-shape-image/bundled-font-readiness-v6-line-limit-host',
    'bundled-font-live': 'text-shape-image/bundled-font-readiness-v3-windows-host',
    'bundled-font-observation': 'text-shape-image/bundled-font-readiness-v2/windows-host',
    'rounded-stroke': 'text-shape-image/rounded-stroke-host-v1',
    'rounded-stroke-centered': 'text-shape-image/rounded-stroke-host-v1/centered-delivery-v1',
    'rounded-stroke-circular': 'text-shape-image/rounded-stroke-host-v1/circular-centered-delivery-v2',
    'rounded-stroke-observation': 'text-shape-image/rounded-stroke-host-v1/continuous-observation-delivery-v3',
    'stack-overlay-centered': 'stack-layout/stack-overlay-centered-execution-v2',
    'stack-overlay-observation': 'stack-layout/stack-overlay-centered-execution-v3',
    'custom-layout': 'stack-layout/custom-layout-host-v1',
    'custom-layout-v2': 'stack-layout/custom-layout-host-v2',
    'custom-layout-centered': 'stack-layout/custom-layout-host-v2/light-centered-delivery-v1',
    'custom-layout-observation': 'stack-layout/custom-layout-host-v2/light-centered-execution-v2',
}
RUNTIME_TREE = 'sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
RUNTIME_COMMIT = '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
RENDERER = 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
COMPILER = '1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
DEP = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"

parser = argparse.ArgumentParser()
parser.add_argument('--host', choices=tuple(PACKETS), required=True)
parser.add_argument('--attempt', type=int, choices=range(1, 11), default=None,
                    help='1 selects plan-prebuild-v4; 2 selects native-r2 Image retry')
parser.add_argument('--compile-revision', type=int, choices=range(1, 11), default=1,
                    help='rolling root compile stage revision')
parser.add_argument('--actual-dir', help='fresh actual-prebuild-rN directory')
parser.add_argument('--stdout-path', help='actual compile.stdout.bin; defaults inside actual-dir')
parser.add_argument('--seed-case-artifact', type=Path,
                    help='original recipe seed when packet case is already materialized; same block/inputs required')
args = parser.parse_args()

attempt = args.attempt if args.attempt is not None else (2 if args.host == 'image' else 1)
out = EXEC / (args.host + f'-compile-r{args.compile_revision}')
plan_name = 'plan-prebuild-native-r2.json' if attempt == 2 and args.host == 'image' else 'plan-prebuild-v4.json'
builder_name = 'build-owned-native-r2.ps1' if args.host == 'image' and attempt == 2 else 'build-owned-pilot-v1.ps1'
actual_dir = Path(args.actual_dir) if args.actual_dir else out / f'actual-prebuild-r{attempt}'
if not actual_dir.is_absolute():
    actual_dir = ROOT / actual_dir
stdout_path = Path(args.stdout_path) if args.stdout_path else actual_dir / 'compile.stdout.bin'
if not stdout_path.is_absolute():
    stdout_path = ROOT / stdout_path
packet = ROOT / 'factory/pipeline/pilot-delivery-five-v1' / PACKETS[args.host] / 'package'
native_plan_path = out / plan_name
builder_path = out / builder_name
receipt_path = actual_dir / 'observation.json'

def stream_hash(path: Path, cap: int = 64 * 1024 * 1024) -> tuple[str, int]:
    if not path.is_file() or path.is_symlink():
        raise RuntimeError(f'bounded regular file required: {path}')
    size = path.stat().st_size
    if size > cap:
        raise RuntimeError(f'file cap exceeded: {path}')
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

def read(path: Path, cap: int = 4 * 1024 * 1024) -> bytes:
    if not path.is_file() or path.is_symlink() or path.stat().st_size > cap:
        raise RuntimeError(f'bounded regular file required: {path}')
    return path.read_bytes()

def digest(path: Path) -> str:
    return stream_hash(path)[0]

def load_json(path: Path):
    return json.loads(read(path).decode('utf-8-sig'))

def require(condition: bool, message: str):
    if not condition:
        raise RuntimeError(message)

sys.path.insert(0, str(ROOT))
from factory.recipes.cases import expand_cases
from factory.tools.canonical_json import sha256 as canonical_sha256

def measured_tuple(host_hash: str, plan_tuple: dict) -> dict:
    """Use shared measured tuple fields; bind only current Windows product hash."""
    known = {
        'sdk': '/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk',
        'macosBuild': '26A434',
        'toolchains': {
            'macSwift': 'Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)\nTarget: arm64-apple-macosx27.0.0',
            'winSwift': 'Swift 6.4.0+Asserts; measured compiler sha256:' + COMPILER,
        },
        'factoryVersion': '0.1-working-observation',
        'acceptanceConfigHash': 'sha256:082fe5a160dba7d326ded1ce1fbbea5a4cc7222aa1d21c2d8778af4babbbd874',
    }
    return {
        'id': str(plan_tuple.get('id') or 'sr1-final-prebuild-r' + str(attempt)),
        'sdk': str(plan_tuple.get('sdk') or known['sdk']),
        'macosBuild': str(plan_tuple.get('macosBuild') or known['macosBuild']),
        'toolchains': plan_tuple.get('toolchains') or known['toolchains'],
        'runtimeCommit': RUNTIME_COMMIT,
        'rendererHash': 'sha256:' + RENDERER,
        'hostHashes': {'windows': host_hash},
        'factoryVersion': str(plan_tuple.get('factoryVersion') or known['factoryVersion']),
        'acceptanceConfigHash': str(plan_tuple.get('acceptanceConfigHash') or known['acceptanceConfigHash']),
    }

RECIPE_REGISTRY = {
    # Gate-seeded RoundedRectangle packets carry a typed recipe reference, not
    # a filesystem path. Keep registry resolution explicit & hash-bound.
    'swiftui.shapes.fill-stroke.recipe': ROOT / 'factory/recipes/data/swiftui.shapes.fill-stroke.json',
    'swiftui.custom-layout.recipe': ROOT / 'factory/recipes/data/swiftui.custom-layout.json',
    'swiftui.text.bundled-font.tinos-pilot.recipe': ROOT / 'factory/resources/fonts/pilot/recipe.json',
}

def _declared_recipe_paths(owner: dict, recipe_id: str) -> list[Path]:
    """Collect only typed recipe paths declared by packet/prebuild metadata."""
    paths: list[Path] = []
    values = []
    if isinstance(owner.get('recipePath'), str):
        values.append(owner['recipePath'])
    for row in owner.get('sourceBindings') or []:
        if not isinstance(row, dict):
            continue
        row_id = row.get('recipeId') or row.get('id')
        if row_id == recipe_id and isinstance(row.get('path'), str):
            values.append(row['path'])
        if row.get('role') == 'recipe' and isinstance(row.get('path'), str):
            values.append(row['path'])
    for value in values:
        candidate = Path(value)
        if not candidate.is_absolute():
            candidate = ROOT / candidate
        paths.append(candidate)
    return paths

def resolve_packet_recipe(case: dict, packet_plan: dict, plan: dict) -> tuple[Path, dict, str]:
    """Resolve recipe path from typed packet metadata & verify canonical hash."""
    reference = case.get('recipe')
    if isinstance(reference, str):
        recipe_path = ROOT / reference
        packet_recipe = load_json(recipe_path)
        packet_recipe_hash = canonical_sha256(packet_recipe)
        provenance_hash = (case.get('provenance') or {}).get('sourceHash')
        if provenance_hash is not None:
            require(provenance_hash == packet_recipe_hash, 'case provenance recipe hash mismatch')
        return recipe_path, packet_recipe, packet_recipe_hash
    require(isinstance(reference, dict), 'case recipe must be path string or typed object')
    recipe_id = reference.get('id')
    recipe_hash = reference.get('hash') or reference.get('canonicalHash')
    require(isinstance(recipe_id, str) and recipe_id, 'typed recipe id missing')
    require(isinstance(recipe_hash, str) and re.fullmatch(r'sha256:[0-9a-f]{64}', recipe_hash),
            'typed recipe hash must be sha256-prefixed lowercase hex')

    # Prospective stack/layout cases declare recipe paths relative to package.
    # Resolve those directly; compiler plans retain the measured source package.
    reference_path = reference.get('path')
    if isinstance(reference_path, str):
        resolved = (packet / reference_path).resolve()
        resolved.relative_to(ROOT)
        declared = [resolved]
    else:
        declared = _declared_recipe_paths(packet_plan, recipe_id) + _declared_recipe_paths(plan, recipe_id)
    registry_path = RECIPE_REGISTRY.get(recipe_id)
    if registry_path is not None:
        declared.append(registry_path)
    unique = {path.resolve() for path in declared}
    require(len(unique) == 1, 'typed recipe did not resolve to one canonical path')
    recipe_path = next(iter(unique))
    packet_recipe = load_json(recipe_path)
    packet_recipe_hash = canonical_sha256(packet_recipe)
    require(packet_recipe.get('id') == recipe_id, 'typed recipe id mismatch')
    require(packet_recipe_hash == recipe_hash, 'typed recipe canonical hash mismatch')
    provenance_hash = (case.get('provenance') or {}).get('sourceHash')
    if provenance_hash is not None:
        provenance = case['provenance']
        if provenance.get('producer') == 'factory/recipes.expand_cases':
            descriptor = {key: case[key] for key in ('id', 'inputs', 'coverage')}
            if 'seed' in case:
                descriptor['seed'] = case['seed']
            require(provenance_hash == canonical_sha256(descriptor), 'case descriptor provenance hash mismatch')
            require({'id': recipe_id, 'hash': packet_recipe_hash} in provenance.get('inputs', []),
                    'case recipe provenance input mismatch')
        else:
            require(provenance_hash == packet_recipe_hash, 'case provenance recipe hash mismatch')
    return recipe_path, packet_recipe, packet_recipe_hash

def materialize_case(case: dict, plan: dict, packet_plan: dict, host_hash: str) -> tuple[dict, dict]:
    """Expand packet recipe into one canonical case, preserving explicit inputs."""
    raw_inputs = case.get('inputs') or case.get('caseInputs') or {}
    axis_key_map = {
        'name': 'name', 'sourceWidth': 'source-width', 'sourceHeight': 'source-height',
        'frameWidth': 'frame-width', 'frameHeight': 'frame-height',
        'colorScheme': 'color-scheme', 'sampling': 'sampling',
        'sourcePixelHash': 'source-pixel-hash',
        'zStackAlignment': 'z-stack-alignment',
        'overlayAlignment': 'overlay-alignment',
        'overlayText': 'overlay-text',
    }
    inputs = {axis_key_map.get(key, key): value for key, value in raw_inputs.items()}
    recipe_case = case
    seed_join = None
    if args.seed_case_artifact is not None:
        seed_path = args.seed_case_artifact
        if not seed_path.is_absolute():
            seed_path = ROOT / seed_path
        seed_path.resolve().relative_to(ROOT)
        seed = load_json(seed_path)
        seed_inputs = {axis_key_map.get(key, key): value
                       for key, value in (seed.get('inputs') or {}).items()}
        require(seed.get('block') == case.get('block'), 'recipe seed block differs from compiled packet')
        require(seed_inputs == inputs and bool(inputs), 'recipe seed inputs differ from compiled packet')
        require(isinstance(case.get('recipe'), dict) and isinstance(seed.get('recipe'), dict),
                'explicit seed join requires typed recipe references')
        require(seed['recipe'].get('id') == case['recipe'].get('id'), 'recipe seed id differs from compiled packet')
        recipe_case = seed
        seed_join = {'path': str(seed_path.relative_to(ROOT)), 'rawSha256': 'sha256:' + digest(seed_path),
                     'id': seed['id'], 'sameBlock': True, 'sameNormalizedInputs': True,
                     'compiledPacketCaseRawSha256': 'sha256:' + digest(packet / 'case.json')}
    recipe_path, packet_recipe, packet_recipe_hash = resolve_packet_recipe(recipe_case, packet_plan, plan)
    recipe = {
        'kind': 'recipe', 'version': '0.1',
        'id': str(packet_recipe.get('id') or case['id'].split('/case/', 1)[0]),
        'provenance': {
            'sourceHash': packet_recipe_hash,
            'createdAt': '2026-10-12T00:00:00Z',
            'producer': 'factory/pipeline/pilot-delivery-five-v1/finalizer',
            'review': {'reviewer': 'root', 'at': '2026-10-12T00:00:00Z', 'decision': 'candidate'},
        },
        'block': case['block'],
        'witnesses': [{
            'id': str(packet_recipe.get('id') or case['id']) + '.witness',
            'sourceHash': plan['sourceHash'],
            'resources': [{'id': 'factory-probe-witness.swift', 'hash': plan['sourceHash']}],
        }],
        'stimuli': [],
        'assertions': [{
            'id': str(packet_recipe.get('id') or case['id']) + '.assertion.primary',
            'channel': 'paint', 'expected': packet_recipe,
            'observability': 'available',
        }],
        'axes': [{'id': key, 'values': [value], 'coverage': 'full-product'}
                 for key, value in inputs.items()],
        'negativeCases': [],
        'instrumentationTransparency': {
            'case': str(packet_recipe.get('id') or case['id']) + '.instrumentation-transparency',
            'channels': ['layout', 'paint'],
        },
    }
    tuple_value = measured_tuple(host_hash, plan.get('tuple') or {})
    expansion = expand_cases(recipe, tuple_value, seed=0,
                              snapshot_created_at='2026-10-12T00:00:00Z')
    # `expand_cases` always adds an instrumentation-transparency case. Its
    # baseline inputs can equal one real row, so input equality alone is not
    # a unique join. Select declared axis row by its explicit full-product
    # coverage, then reject any remaining ambiguity.
    matches = [item for item in expansion['cases']
               if item.get('inputs') == inputs and item.get('coverage') == 'full-product']
    require(len(matches) == 1, 'materialized case input did not resolve uniquely')
    return matches[0], {
        'recipe': recipe,
        'recipeHash': canonical_sha256(recipe),
        'packetRecipePath': str(recipe_path.relative_to(ROOT)).replace('\\', '/'),
        'packetRecipeCanonicalHash': packet_recipe_hash,
        'packetCaseId': case['id'],
        'recipeSeedJoin': seed_join,
        'rawInputs': raw_inputs,
        'inputKeyMap': axis_key_map,
        'axisJoin': {
            'normalizedInputs': inputs,
            'selectedCoverage': 'full-product',
            'selectedCaseId': matches[0]['id'],
            'candidateCount': len(matches),
            'transparencyRowsExcluded': sum(
                item.get('inputs') == inputs and item.get('coverage') == 'declared'
                for item in expansion['cases']
            ),
        },
        'packetCaseRawJsonHash': 'sha256:' + digest(packet / 'case.json'),
        'caseSetHash': expansion['manifest']['expectedCaseSetHash'],
    }

def scan_frontend(path: Path) -> dict:
    """Stream stdout & prove every swift-frontend command ends at one thread."""
    commands: list[dict] = []
    pending = b''
    with path.open('rb') as handle:
        while True:
            chunk = handle.read(64 * 1024)
            if not chunk:
                break
            data = pending + chunk
            lines = data.splitlines(keepends=True)
            pending = lines.pop() if lines and not lines[-1].endswith((b'\n', b'\r')) else b''
            for line in lines:
                text = line.decode('utf-8', 'replace')
                if 'swift-frontend.exe -frontend' not in text:
                    continue
                values = [int(match.group(1)) for match in re.finditer(r'-num-threads\s+(\d+)', text)]
                require(values and values[-1] == 1, 'each swift-frontend command must end with -num-threads 1')
                commands.append({'index': len(commands) + 1, 'command': text.rstrip('\r\n'),
                                 'numThreadsValues': values, 'lastNumThreads': values[-1]})
    if pending:
        text = pending.decode('utf-8', 'replace')
        if 'swift-frontend.exe -frontend' in text:
            values = [int(match.group(1)) for match in re.finditer(r'-num-threads\s+(\d+)', text)]
            require(values and values[-1] == 1, 'each swift-frontend command must end with -num-threads 1')
            commands.append({'index': len(commands) + 1, 'command': text.rstrip('\r\n'),
                             'numThreadsValues': values, 'lastNumThreads': values[-1]})
    require(commands, 'no swift-frontend -frontend command proof found')
    values = [value for command in commands for value in command['numThreadsValues']]
    file_hash, file_bytes = stream_hash(path)
    return {
        'path': str(path), 'sha256': 'sha256:' + file_hash, 'bytes': file_bytes,
        'frontendCommandCount': len(commands), 'frontendCommands': commands,
        'numThreadsOccurrenceCount': len(values), 'numThreadsValues': values,
        'lastNumThreads': values[-1], 'requiredLastNumThreads': 1,
        'proof': 'actual-stdout-stream-scan',
    }

packet_plan_raw = packet / 'plan.json'
packet_plan = load_json(packet_plan_raw)
case_raw_path = packet / 'case.json'
case = load_json(case_raw_path)
plan = load_json(native_plan_path)
receipt = load_json(receipt_path)

require(plan.get('kind') == 'factory-pilot-five-compiler-plan-v1', 'prebuild plan kind mismatch')
require(plan.get('phase') == 'prebuild' and plan.get('executionEligible') is False, 'prebuild phase gate mismatch')
require(plan.get('case') is None and plan.get('expectedHostHash') is None, 'prebuild already contains final bindings')
require(plan.get('runtimeSourceCommit') == RUNTIME_COMMIT, 'runtime commit drift')
require(plan.get('runtimeSourceTreeHash') == RUNTIME_TREE, 'runtime tree drift')
require(str(plan.get('rendererSha256')).removeprefix('sha256:') == RENDERER, 'renderer drift')
require(str(plan.get('compilerHash')).removeprefix('sha256:') == COMPILER, 'compiler drift')
require(plan.get('packageSourcePath') == f'factory/pipeline/pilot-delivery-five-v1/{PACKETS[args.host]}/package', 'packet source path drift')
require(plan.get('packetPlanHash') == 'sha256:' + digest(packet_plan_raw), 'packet plan hash drift')
require(plan.get('candidate') == packet_plan.get('candidate', load_json(packet / 'case.json')['block'] + '.pilot'), 'candidate drift')

source_rows = plan.get('sourceBindings') or []
seen: set[str] = set(); total = 0
for row in source_rows:
    rel = row.get('path')
    require(isinstance(rel, str) and rel and not rel.startswith(('/', '\\')) and '\\' not in rel and ':' not in rel and '..' not in Path(rel).parts, 'unsafe source binding')
    require(rel not in seen, 'duplicate source binding')
    seen.add(rel)
    source_hash, source_bytes = stream_hash(packet / rel)
    total += source_bytes
    require(source_bytes == row.get('bytes') and source_hash == str(row.get('sha256')).replace('sha256:', ''), 'source binding drift')
require(len(source_rows) <= 256 and total <= 268435456, 'source bounds exceeded')

compile_request = plan.get('compileRequest') or {}
package_path = compile_request.get('packagePath')
scratch_path = compile_request.get('scratchPath')
require(isinstance(package_path, str) and isinstance(scratch_path, str), 'compile paths missing')
require(plan.get('packageStagePath') in (package_path, package_path.removesuffix('\\package')),
        'packet stage must identify exact compiler package or its owning stage')
require(package_path.endswith('\\package') and scratch_path.startswith(package_path + '\\'), 'compile path namespace drift')
require(compile_request.get('buildSystem') == 'native', 'native build system missing')
expected_argv = [
    'build', '--build-system', 'native', '-v', '--package-path', package_path,
    '--scratch-path', scratch_path, '--jobs', '1', '-Xswiftc', '-j1',
    '-Xswiftc', '-num-threads', '-Xswiftc', '1', '-c', 'release',
    '-Xlinker', '/MANIFEST:EMBED', '-Xlinker', DEP,
    '-Xlinker', '/SUBSYSTEM:WINDOWS', '-Xlinker', '/ENTRY:mainCRTStartup',
]
require(compile_request.get('argv') == expected_argv, 'compile argv is not exact native bounded request')
require(compile_request.get('maxParallelJobs') == 1 and compile_request.get('maxFrontendThreads') == 1, 'parallelism bound drift')
require(compile_request.get('memoryCapBytes') == 1073741824, 'memory cap drift')
expected_command = (
    'build --build-system native -v --package-path "' + package_path +
    '" --scratch-path "' + scratch_path + '" --jobs 1 -Xswiftc -j1 '
    '-Xswiftc -num-threads -Xswiftc 1 -c release -Xlinker /MANIFEST:EMBED '
    '-Xlinker "' + DEP + '" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
)
require(receipt.get('planSha256') == digest(native_plan_path), 'receipt plan hash mismatch: raw SHA256 required')
rounded_argv = [
    'build', '--package-path', package_path, '--scratch-path', scratch_path,
    '--build-system', 'native', '-v', '--jobs', '1', '-Xswiftc', '-j1',
    '-Xswiftc', '-num-threads', '-Xswiftc', '1', '-c', 'release',
    '-Xlinker', '/MANIFEST:EMBED', '-Xlinker', DEP,
    '-Xlinker', '/SUBSYSTEM:WINDOWS', '-Xlinker', '/ENTRY:mainCRTStartup',
]
rounded_command = (
    'build --package-path "' + package_path + '" --scratch-path "' + scratch_path +
    '" --build-system native -v --jobs 1 -Xswiftc -j1 '
    '-Xswiftc -num-threads -Xswiftc 1 -c release -Xlinker /MANIFEST:EMBED '
    '-Xlinker "' + DEP + '" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
)
actual_command = receipt.get('argv')
if args.host == 'rounded-stroke' and actual_command == rounded_command:
    actual_argv = rounded_argv
    argv_ordering = {
        'declared': 'native-before-package',
        'actual': 'package-before-native',
        'defect': True,
        'source': 'retained-prebuild-builder-receipt',
    }
else:
    require(actual_command == expected_command, 'actual builder argv mismatch')
    actual_argv = expected_argv
    argv_ordering = {
        'declared': 'native-before-package',
        'actual': 'native-before-package',
        'defect': False,
        'source': 'retained-prebuild-builder-receipt',
    }
for key, expected in {
    'sourceHash': plan.get('sourceHash'), 'runtimeSourceCommit': RUNTIME_COMMIT,
    'runtimeSourceTreeHash': RUNTIME_TREE, 'compilerHash': plan['compilerHash'],
    'rendererSha256': plan['rendererSha256'], 'target': 'windows-x86_64', 'configuration': 'release',
    'exitCode': 0, 'timedOut': False, 'outputCapExceeded': False, 'ownedExited': True,
    'streamDrainComplete': True, 'streamsSealed': True, 'originalHandleRetained': True,
    'jobActiveReadable': True, 'jobActiveCount': 0, 'kernelWait': 0,
    'cleanupJobReadable': True, 'cleanupJobActive': 0, 'nativeActions': 0,
}.items():
    require(receipt.get(key) == expected, f'prebuild receipt gate failed: {key}')

stdout_evidence = scan_frontend(stdout_path)
require(receipt.get('stdoutSha256', '').replace('sha256:', '') == stdout_evidence['sha256'].replace('sha256:', ''), 'stdout hash drift')
require(receipt.get('stdoutBytes') == stdout_evidence['bytes'], 'stdout byte count drift')
stderr_path = actual_dir / 'compile.stderr.bin'
stderr_hash, stderr_bytes = stream_hash(stderr_path)
require(receipt.get('stderrSha256', '').replace('sha256:', '') == stderr_hash, 'stderr hash drift')
require(receipt.get('stderrBytes') == stderr_bytes, 'stderr byte count drift')
exe_candidate = actual_dir / 'FactoryProbe.exe'
exe_hash, exe_bytes = stream_hash(exe_candidate)
require(receipt.get('exeSha256', '').replace('sha256:', '') == exe_hash, 'native product hash drift')
require(receipt.get('exeBytes') == exe_bytes, 'native product size drift')
require(receipt.get('exePath') == scratch_path + '\\x86_64-unknown-windows-msvc\\release\\FactoryProbe.exe', 'native product path mismatch')
host_hash = 'sha256:' + exe_hash
materialized_case, case_meta = materialize_case(case, plan, packet_plan, host_hash)
case_hash = canonical_sha256(materialized_case)
case_binding = {'id': materialized_case['id'], 'hash': case_hash}

final_plan = json.loads(json.dumps(plan))
final_plan.update({
    'kind': 'factory-pilot-five-compiler-plan-v1',
    'phase': 'final', 'case': case_binding, 'caseHash': case_hash,
    'canonicalCaseHash': case_hash,
    'caseRawJsonHash': 'sha256:' + digest(case_raw_path),
    'hostHash': host_hash, 'expectedHostHash': host_hash,
    'executionEligible': False,
    'nativeParity': 'prebuild-validated-final-build-pending',
    'status': 'final-plan-ready-pending-final-build',
    'prebuildReceipt': str(receipt_path.relative_to(ROOT)).replace('\\', '/'),
    'prebuildReceiptHash': 'sha256:' + digest(receipt_path),
    'materializedCase': materialized_case,
    'caseMaterialization': case_meta,
    'frontendCommandScan': stdout_evidence,
    'compileRequestArgvOrdering': argv_ordering,
    'actualPrebuildArgv': actual_argv,
    'outputs': {'prebuildExePath': receipt['exePath'], 'prebuildExeSha256': host_hash, 'prebuildExeBytes': exe_bytes},
})
tuple_data = materialized_case['tuple']
tuple_data['hostHashes']['windows'] = host_hash
final_plan['tuple'] = tuple_data

final_plan_path = out / 'plan-final-v4.json'
for protected_output in (final_plan_path, out / 'build-owned-final-v1.ps1',
                         out / 'final-builder-request.json', out / 'final-remote-entry.ps1',
                         out / 'materialized-case.json', out / 'finalization.json',
                         out / 'observation.json'):
    require(not protected_output.exists(), f'refuse overwrite of historical output: {protected_output}')
final_plan_path.write_text(json.dumps(final_plan, indent=2, sort_keys=True) + '\n')
builder = read(builder_path, 16 * 1024 * 1024).decode('utf-8')
candidate_predicate = re.compile(r"\$plan\.candidate -cne '[^']*'")
require(len(candidate_predicate.findall(builder)) == 1, 'builder candidate predicate missing or duplicated')
builder = candidate_predicate.sub("$plan.candidate -cne '" + plan['candidate'] + "'", builder, count=1)
case_predicate = re.compile(r"\$plan\.case\.id -notlike '[^']*'")
require(case_predicate.search(builder) is not None, 'builder case predicate missing')
builder = case_predicate.sub("$plan.case.id -cne '" + materialized_case['id'] + "'", builder, count=1)
final_builder_path = out / 'build-owned-final-v1.ps1'
final_builder_path.write_text(builder, encoding='utf-8')
builder_hash = digest(final_builder_path)
final_plan_hash = digest(final_plan_path)
receipt_hash = digest(receipt_path)

request = {
    'kind': 'factory-pilot-five-bounded-final-builder-request-v1', 'host': args.host,
    'phase': 'final', 'attempt': 1,
    'planPath': str(final_plan_path), 'planSha256': final_plan_hash,
    'builderPath': str(final_builder_path), 'builderSha256': 'sha256:' + builder_hash,
    'prebuildPlanPath': str(native_plan_path), 'prebuildBuilderPath': str(builder_path),
    'actualPrebuildReceipt': str(receipt_path), 'actualPrebuildReceiptHash': 'sha256:' + receipt_hash,
    'packagePath': package_path, 'scratchPath': scratch_path, 'argv': actual_argv,
    'declaredCompileRequestArgv': expected_argv,
    'argvOrderingDefect': argv_ordering,
    'actualReceiptArgv': actual_command,
    'memoryCapBytes': 1073741824, 'maxParallelJobs': 1, 'maxFrontendThreads': 1,
    'case': case_binding, 'caseHash': case_hash, 'canonicalCaseHash': case_hash,
    'caseRawJsonHash': 'sha256:' + digest(case_raw_path), 'expectedHostHash': host_hash,
    'nativeProductPath': receipt['exePath'], 'nativeActions': 0,
    'executionEligible': True, 'frontendCommandScan': stdout_evidence,
    'captureGate': 'root-final-build-receipt-then-native-count1-before-count20',
}
request_path = out / 'final-builder-request.json'
request_path.write_text(json.dumps(request, indent=2, sort_keys=True) + '\n')

remote_entry_path = out / 'final-remote-entry.ps1'
remote_entry = f'''# Root-owned guarded final entry; archive prebuild inputs before copy.
param([switch]$PreflightOnly)
$ErrorActionPreference = 'Stop'
$stage = 'D:\\Claude\\swiftright\\.factory-work\\hosts\\{args.host}'
$archive = Join-Path $stage 'prebuild-archive-attempt-{attempt}'
$finalReceipt = Join-Path $stage 'final-r1\\observation.json'
$planTarget = Join-Path $stage 'package\\plan-final-v4.json'
$builderTarget = Join-Path $stage 'build-owned-final-v1.ps1'
$requestRoot = $PSScriptRoot
if ($PreflightOnly) {{
  if ((Test-Path -LiteralPath $finalReceipt) -or (Test-Path -LiteralPath $archive)) {{ throw 'preflight requires untouched final stage' }}
  if ((Test-Path -LiteralPath $planTarget) -or (Test-Path -LiteralPath $builderTarget)) {{ throw 'preflight refuses existing final inputs' }}
  $requestPlan = Join-Path $requestRoot 'plan-final-v4.json'
  $requestBuilder = Join-Path $requestRoot 'build-owned-final-v1.ps1'
  if (-not (Test-Path -LiteralPath $requestPlan) -or -not (Test-Path -LiteralPath $requestBuilder)) {{ throw 'preflight request files missing' }}
  $planHash = (Get-FileHash -LiteralPath $requestPlan -Algorithm SHA256).Hash.ToLowerInvariant()
  $builderHash = (Get-FileHash -LiteralPath $requestBuilder -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($planHash.Length -ne 64 -or $builderHash.Length -ne 64) {{ throw 'preflight request hashes unavailable' }}
  [ordered]@{{status='request-inputs-ready'; preflightKind='hash-only-request-input-preflight'; compilerAdmission=$false; builderPreflightRequired=$true; planSha256=$planHash; builderSha256=$builderHash; archiveCreated=$false; finalInputsInstalled=$false; nativeActions=0}} | ConvertTo-Json -Compress
  exit 0
}}
if (Test-Path -LiteralPath $finalReceipt) {{ throw 'refuse overwrite of existing final receipt' }}
if (Test-Path -LiteralPath $archive) {{ throw 'refuse overwrite of prebuild archive' }}
if ((Test-Path -LiteralPath $planTarget) -or (Test-Path -LiteralPath $builderTarget)) {{ throw 'refuse overwrite of final inputs' }}
New-Item -ItemType Directory -Path $archive | Out-Null
Copy-Item -LiteralPath (Join-Path $requestRoot '{plan_name}') -Destination (Join-Path $archive '{plan_name}')
Copy-Item -LiteralPath (Join-Path $requestRoot '{builder_name}') -Destination (Join-Path $archive '{builder_name}')
Copy-Item -LiteralPath (Join-Path $requestRoot 'plan-final-v4.json') -Destination $planTarget
Copy-Item -LiteralPath (Join-Path $requestRoot 'build-owned-final-v1.ps1') -Destination $builderTarget
$planHash = (Get-FileHash -LiteralPath $planTarget -Algorithm SHA256).Hash.ToLowerInvariant()
$builderPreflight = @(& $builderTarget -PlanPath $planTarget -PlanSha256 $planHash -Phase final -Attempt 1 -PreflightOnly)
if ($builderPreflight.Count -eq 0) {{ throw 'builder PreflightOnly returned no success record' }}
$builderPreflightRecord = ($builderPreflight -join "`n") | ConvertFrom-Json
if ($builderPreflightRecord.status -cne 'passed') {{ throw 'builder PreflightOnly did not return passed status' }}
& $builderTarget -PlanPath $planTarget -PlanSha256 $planHash -Phase final -Attempt 1
'''
remote_entry_path.write_text(remote_entry, encoding='utf-8')

(out / 'materialized-case.json').write_text(json.dumps(materialized_case, indent=2, sort_keys=True) + '\n')
(out / 'finalization.json').write_text(json.dumps({
    'kind': 'factory-pilot-five-finalization-v1', 'host': args.host, 'attempt': attempt,
    'status': 'validated-final-plan-written-pending-final-receipt', 'nativeActions': 0,
    'case': case_binding, 'caseHash': case_hash, 'canonicalCaseHash': case_hash,
    'caseRawJsonHash': 'sha256:' + digest(case_raw_path), 'hostHash': host_hash,
    'plan': str(final_plan_path), 'request': str(request_path),
    'remoteEntry': str(remote_entry_path), 'prebuildReceipt': str(receipt_path),
    'executionEligible': False, 'requestExecutionEligible': True,
}, indent=2, sort_keys=True) + '\n')
print(json.dumps({
    'host': args.host, 'attempt': attempt, 'status': 'validated-final-plan-written-pending-final-receipt',
    'case': case_binding, 'hostHash': host_hash, 'plan': str(final_plan_path),
    'request': str(request_path), 'remoteEntry': str(remote_entry_path), 'nativeActions': 0,
}, sort_keys=True))
