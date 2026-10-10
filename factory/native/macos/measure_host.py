"""Postclosure case-independent Mac host measurement; no capture or prompt APIs."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import subprocess

from factory.native.macos.capture import REPO, DEFAULT_SCRATCH, CaptureError, digest, internal_scratch, logged, write

QUALIFICATION_SOURCE = 'import SwiftUI\nstruct FactoryHostQualification: View { var body: some View { Text("Factory host qualification").frame(width: 64, height: 32) } }\n'

def utc(value: str) -> datetime:
    if not isinstance(value, str) or not value.endswith('Z'):
        raise CaptureError('closure time must be UTC')
    return datetime.fromisoformat(value[:-1] + '+00:00')

def require_closure(status: Path, receipt: Path, runtime_commit: str) -> dict:
    text = status.read_text()
    overall = re.findall(r'^\*\*Overall:\s*(.+?)\*\*', text, re.M)
    if len(overall) != 1 or not re.match(r'SR0 is CLOSED\b', overall[0]) or not re.search(r'tuple\s*0?10\b', overall[0], re.I):
        raise CaptureError('explicit CLOSED tuple10 status required before host build/measurement')
    closure = json.loads(receipt.read_text())
    from factory.pipeline.workflow import synthetic
    if synthetic(closure):
        raise CaptureError('synthetic closure receipt cannot authorize host measurement')
    if closure.get('tuple') != '10' or closure.get('decision') != 'CLOSED' or closure.get('statusHash') != digest(status):
        raise CaptureError('closure receipt must bind exact CLOSED tuple10 status bytes')
    if datetime.now(timezone.utc) <= utc(closure.get('closedAt')):
        raise CaptureError('host measurement must occur after closure')
    if not re.fullmatch(r'[0-9a-f]{40}', runtime_commit): raise CaptureError('full runtime commit required')
    from factory.pipeline.tuple10 import staging_pins
    if runtime_commit == staging_pins(REPO/'docs/sr0-tuple10-staging.md')['stagedRuntimeCommit']:
        raise CaptureError('factory runtime commit must be separate from staged SR0 runtime')
    actual = subprocess.check_output(['git', 'rev-parse', '--verify', runtime_commit + '^{commit}'], cwd=REPO, text=True).strip()
    if actual != runtime_commit: raise CaptureError('runtime commit is not actual repository commit')
    runtime_path = 'probes/sr0-s/fresh-runtime'
    changed = subprocess.run(['git', 'diff', '--quiet', runtime_commit, '--', runtime_path], cwd=REPO).returncode
    untracked = subprocess.check_output(['git', 'ls-files', '--others', '--exclude-standard', '--', runtime_path], cwd=REPO, text=True).strip()
    if changed or untracked: raise CaptureError('current factory runtime source must match supplied committed runtime identity')
    return {'tuple': '10', 'decision': 'CLOSED', 'statusPath': str(status.resolve()), 'statusHash': digest(status), 'receiptPath': str(receipt.resolve()), 'receiptHash': digest(receipt), 'closedAt': closure['closedAt']}

def measure(output: Path, scratch: Path, runtime_commit: str, receipt: Path, status: Path) -> dict:
    closure = require_closure(status, receipt, runtime_commit)
    scratch = internal_scratch(scratch)
    if output.exists(): raise CaptureError('measurement output exists; preserve historical bytes')
    output.mkdir(parents=True)
    work = scratch/'case-independent-host'
    if work.exists(): raise CaptureError('use new internal scratch subtree for host measurement')
    work.mkdir(parents=True)
    source = work/'Witness.swift'; source.write_text(QUALIFICATION_SOURCE)
    adapter = Path(__file__).with_name('CaptureHost.swift')
    adapter_snapshot = work/'AdapterTemplate.swift.txt'; adapter_snapshot.write_bytes(adapter.read_bytes())
    adapted = work/'CaptureHost.swift'; adapted.write_text(adapter.read_text().replace('__WITNESS_TYPE__', 'FactoryHostQualification'))
    binary = work/'factory-host-qualification'
    build = logged(['/usr/bin/xcrun', 'swiftc', '-parse-as-library', '-O', '-o', str(binary), str(source), str(adapted)], output/'build', 120)
    if build.returncode: raise CaptureError('case-independent native host build failed')
    preflight = logged([str(binary), '--preflight'], output/'native-no-prompt-preflight')
    if preflight.returncode: raise CaptureError('native host inventory failed')
    inventory = json.loads(preflight.stdout)
    toolchain = {}
    for key, command in {'swift': ['/usr/bin/xcrun', 'swiftc', '--version'], 'sdk': ['/usr/bin/xcrun', '--show-sdk-path'], 'xcode': ['/usr/bin/xcodebuild', '-version'], 'os': ['/usr/bin/sw_vers'], 'architecture': ['/usr/bin/uname', '-m']}.items():
        result = logged(command, output/key)
        if result.returncode: raise CaptureError(f'host inventory command failed: {key}')
        toolchain[key] = result.stdout.strip()
    measured = {'kind': 'macos-factory-host-measurement', 'version': '0.1', 'platform': 'macos', 'tupleIndependent': True, 'measuredAt': datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'), 'runtimeCommit': runtime_commit, 'runtimeLinkage': 'SwiftUI-only host; commit binds factory tuple context, not linked runtime dependency', 'closure': closure, 'source': {'path': str(source), 'hash': digest(source)}, 'adapterSource': {'path': str(adapter_snapshot), 'hash': digest(adapter_snapshot)}, 'adapterRepositoryPath': str(adapter), 'compiledAdapter': {'path': str(adapted), 'hash': digest(adapted)}, 'binary': {'path': str(binary), 'hash': digest(binary)}, 'toolchain': toolchain, 'host': {'display': inventory['display'], 'fontInventory': inventory['fontInventory']}, 'permissions': {key: inventory[key] for key in ('axTrusted', 'screenCaptureGranted', 'permissionRequests')}, 'nativeInventoryHash': digest(output/'native-no-prompt-preflight.stdout.txt'), 'permissionPolicy': 'denied no-prompt grants hold corresponding channel; never request permissions', 'caseOrTupleEmbedded': False}
    write(output/'host-measurement.json', measured)
    return measured

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--runtime-commit', required=True)
    parser.add_argument('--closure-receipt', type=Path, required=True)
    parser.add_argument('--status', type=Path, default=REPO/'docs/sr0-status.md')
    args = parser.parse_args()
    value = measure(args.output, args.scratch, args.runtime_commit, args.closure_receipt, args.status)
    print(json.dumps({'path': str((args.output/'host-measurement.json').resolve()), 'hash': digest(args.output/'host-measurement.json'), 'permissions': value['permissions']}))
    return 0

if __name__ == '__main__':
    try: raise SystemExit(main())
    except (CaptureError, OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f'F5 host measurement: {exc}'); raise SystemExit(2)
