#!/usr/bin/env python3
"""SOURCE-CONTROL capsule for WindowsExitProof against preserved old-r3 bytes.

This script never constructs an admitted capture. Synthetic IDs are marked
control-only; every proof role and every attempted transitive read comes from
pinned old-r3 bytes. Native/lock/remote actions are impossible here.
"""
from __future__ import annotations
import argparse, hashlib, importlib, json, re, sys
from pathlib import Path

ROLES = ('outcome','observation','owned','close','plan','compile','witness','exe','renderer',
         'runtimeReceipt','runtimeTree','stdout','stderr')

def digest(raw: bytes) -> str:
    return 'sha256:' + hashlib.sha256(raw).hexdigest()

def load_json(path: Path):
    return json.loads(path.read_bytes().decode('utf-8-sig'))

def read_ref(repo: Path, ref: dict) -> bytes:
    path = repo / ref['path']
    raw = path.read_bytes()
    if digest(raw) != ref['sha256'] or len(raw) != ref['bytes']:
        raise ValueError(f"pinned source byte mismatch:{ref['path']}")
    return raw

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo', type=Path, default=Path('.'))
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    repo = args.repo.resolve(strict=True)
    base = repo / 'factory/native/windows/padding-capture-lease-capture-v3/root-actual-controls-v1'
    inputs = load_json(base / 'count1-inputs-r6.actual.json')
    run = inputs['runs'][0]
    roles = inputs['roles']
    source = inputs['source']
    role_refs = {
        'outcome': run['outcome'],
        'observation': run['observation'],
        'owned': run['owned'],
        'close': run['close'],
        'plan': roles['plan'],
        'compile': roles['compile'],
        'witness': source['Sources/FactoryProbe/Witness.swift'],
        'exe': roles['exe'],
        'renderer': roles['renderer'],
        'runtimeReceipt': source['runtime-source-receipt.json'],
        'runtimeTree': source['runtime-source-tree.json'],
        'stdout': run['stdout'],
        'stderr': run['stderr'],
    }
    raw = {role: read_ref(repo, ref) for role, ref in role_refs.items()}
    assert set(raw) == set(ROLES)
    plan = load_json(repo / roles['plan']['path'])
    compile_record = load_json(repo / roles['compile']['path'])
    observation = load_json(repo / run['observation']['path'])
    close = load_json(repo / run['close']['path'])
    exe_hash = digest(raw['exe'])
    renderer_hash = digest(raw['renderer'])
    witness_hash = digest(raw['witness'])
    proof = {
        'version': 1,
        'files': {
            role: {'path': f'control-only/r3/roles/{role}.raw', 'hash': digest(raw[role])}
            for role in ROLES
        },
    }
    # Synthetic identity is explicit and cannot be interpreted as production evidence.
    capture = {
        'controlOnly': True,
        'controlOnlyID': 'control-only/windows-exit-proof-r3-legacy-mismatch',
        'platform': 'windows',
        'case': plan['case'],
        'tuple': {'rendererHash': renderer_hash},
        'provenance': {'sourceHash': witness_hash},
        'meta': {
            'controlOnly': True,
            'captureID': 'control-only/capture/r3',
            'imageID': 'control-only/image/r3',
            'run': 1,
            'host': {'hash': exe_hash},
            'clock': {'correlationHash': digest(raw['observation'])},
            'conditions': {
                'windowsExitProof': proof,
                'actualSourceHash': witness_hash,
                'actualHostExecutableHash': exe_hash,
                'actualRendererHash': renderer_hash,
                'rawReceiptHash': digest(raw['observation']),
            },
        },
    }
    sys.path.insert(0, str(repo))
    gate = importlib.import_module('factory.gate.windows_exit_admission')
    read_counts = {role: 0 for role in ROLES}
    transitive = {}
    missing = []
    def reader(path: str) -> bytes:
        # Proof paths are mapped to exact preserved role bytes.
        prefix = 'control-only/r3/roles/'
        if path.startswith(prefix) and path.endswith('.raw'):
            role = path[len(prefix):-4]
            if role in raw:
                read_counts[role] += 1
                return raw[role]
        # Keep explicit transitive source names visible; no fallback/discovery.
        if path == 'tool/compiler.bin':
            missing.append(path)
            raise FileNotFoundError(path)
        missing.append(path)
        raise FileNotFoundError(path)
    result = gate.verify_windows_exit_admission(capture, read_bytes=reader)

    # Run exact compile/argv predicates separately so source control reaches them
    # even when preserved legacy capture fails earlier or compiler transport is held.
    compile_checks = []
    request = plan['compileRequest']
    try:
        expected_argv = gate._production_compile_argv(request)
        compile_checks.extend([
            {'name': 'production-argv', 'pass': compile_record['argv'] == expected_argv},
            {'name': 'production-cwd', 'pass': compile_record['cwd'] == request['packagePath']},
            {'name': 'production-target', 'pass': compile_record['target'] == request['target']},
            {'name': 'production-configuration', 'pass': compile_record['configuration'] == request['configuration']},
            {'name': 'production-compiler-path', 'pass': compile_record['compilerPath'] == request['compilerPath'] == plan['compilerPath']},
            {'name': 'production-exit', 'pass': compile_record['exitCode'] == 0 and compile_record['timedOut'] is False and compile_record['ownedExited'] is True},
            {'name': 'production-output-hash', 'pass': compile_record['exeSha256'] == roles['exe']['sha256'].removeprefix('sha256:')},
            {'name': 'compiler-hash-shape', 'pass': bool(re.fullmatch(r'[0-9a-f]{64}', compile_record['compilerHash'])) and compile_record['compilerHash'] == plan['compilerHash'].removeprefix('sha256:')},
        ])
    except Exception as exc:
        compile_checks.append({'name': 'production-argv', 'pass': False, 'error': str(exc)})
    # Explicitly record unavailable compiler transport; do not synthesize bytes.
    compiler_transport = {
        'path': 'tool/compiler.bin',
        'expectedSha256': 'sha256:' + compile_record['compilerHash'],
        'available': False,
        'action': 'held; no compiler bytes synthesized',
    }
    # Legacy mismatch is measured from actual old-r3 docs, independently of gate labels.
    legacy = []
    if 'ownedIdentity' not in observation:
        legacy.append({
            'predicate': 'observation/ownedIdentity missing',
            'actualKeys': sorted(observation),
        })
    if observation.get('hwnd') != close.get('hwnd'):
        legacy.append({
            'predicate': 'observation/WM_CLOSE HWND mismatch',
            'observationHwnd': observation.get('hwnd'),
            'closeHwnd': close.get('hwnd'),
        })
    result_doc = {
        'schema': 'windows-exit-proof-source-control-r1',
        'status': 'blocked',
        'controlOnly': True,
        'nativeWindowActions': 0,
        'source': 'actual old-r3 pinned raw bytes',
        'proofRoles': list(ROLES),
        'proofRoleHashesVerified': all(read_counts[r] == 1 for r in ROLES),
        'proofRoleReads': read_counts,
        'gate': {
            'status': result['status'],
            'issues': result['issues'],
            'nativeParityGranted': result['nativeParityGranted'],
        },
        'compileArgvChecks': compile_checks,
        'compilerTransport': compiler_transport,
        'legacyMismatches': legacy,
        'missingTransitiveRefs': sorted(set(missing)),
        'ids': {
            'captureID': capture['meta']['captureID'],
            'imageID': capture['meta']['imageID'],
            'productionAdmission': False,
            'parityClaim': False,
        },
    }
    if args.output.exists():
        raise ValueError('output must be fresh')
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result_doc, indent=2, sort_keys=True) + '\n', encoding='utf-8')
    print(json.dumps({
        'status': result_doc['status'],
        'gateStatus': result['status'],
        'issues': result['issues'],
        'proofRolesRead': sum(read_counts.values()),
        'compileChecks': sum(1 for c in compile_checks if c.get('pass')),
        'legacyMismatches': legacy,
        'nativeWindowActions': 0,
    }, sort_keys=True))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
