#!/usr/bin/env python3
"""No-prompt native candidate collector. Fresh executables live on internal disk."""
from __future__ import annotations
import argparse
import json
import os
import signal
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone

def _repo_root() -> Path:
    injected = os.environ.get('SWIFTRIGHT_REPO_ROOT')
    candidates = []
    if injected:
        candidates.append(Path(injected).expanduser().resolve())
    candidates.extend(Path(__file__).resolve().parents)
    for candidate in candidates:
        marker = candidate / 'factory' / 'core' / 'artifacts.py'
        oracle = candidate / 'factory' / 'oracle'
        if marker.is_file() and oracle.is_dir():
            return candidate
    raise RuntimeError('repository root marker factory/core/artifacts.py not found')

REPO = _repo_root()
sys.path.insert(0, str(REPO))
if not __import__('importlib.util', fromlist=['find_spec']).find_spec('jsonschema'):
    for packages in (REPO / 'factory/.venv/lib').glob('python*/site-packages'):
        sys.path.insert(0, str(packages))
from factory.core.artifacts import provenance

DEFAULT_SCRATCH = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1')
PILOTS = ('swiftui.shapes.fill-stroke', 'swiftui.image', 'swiftui.stack-overlay', 'swiftui.text.bundled-font', 'swiftui.text.layout.baseline', 'swiftui.custom-layout', 'swiftui.scroll-view', 'swiftui.toggle', 'swiftui.disabled', 'swiftui.padding-frame', 'swiftui.preference-key')
RECORDER = Path.home() / 'Applications/SwiftRight/F1MacRecord.app'  # one fixed install path (rule 2026-10-17)

class CaptureError(ValueError): pass

def digest(path: Path, max_bytes: int = 64 * 1024 * 1024) -> str:
    if path.is_symlink():
        raise CaptureError(f'bounded regular file required: {path}')
    st = path.stat()
    if not path.is_file() or st.st_size > max_bytes:
        raise CaptureError(f'bounded regular file required: {path}')
    import hashlib
    h = hashlib.sha256()
    deadline = time.monotonic() + 30
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024):
            if time.monotonic() > deadline:
                raise CaptureError(f'bounded digest deadline exceeded: {path}')
            h.update(chunk)
    return 'sha256:' + h.hexdigest()

def copy_bounded(source: Path, destination: Path, max_bytes: int = 64 * 1024 * 1024) -> None:
    if source.is_symlink():
        raise CaptureError(f'bounded regular file required: {source}')
    st = source.stat()
    if not source.is_file() or st.st_size > max_bytes:
        raise CaptureError(f'bounded regular file required: {source}')
    destination.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + 30
    with source.open('rb') as src, destination.open('wb') as dst:
        while chunk := src.read(1024 * 1024):
            if time.monotonic() > deadline:
                raise CaptureError(f'bounded copy deadline exceeded: {source}')
            dst.write(chunk)

def write(path: Path, obj: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, sort_keys=True, indent=2) + '\n')

def internal_scratch(path: Path) -> Path:
    path = path.expanduser().resolve()
    allowed = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory').resolve()
    if not path.is_relative_to(allowed) or path == allowed:
        raise CaptureError('scratch must be child of internal SwiftRightFactory cache')
    return path

def bounded_text(path: Path, limit: int = 8 * 1024 * 1024) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        raise CaptureError(f'bounded command log required: {path}')
    return path.read_text(errors='replace')

def run(command: list[str], timeout: int = 60, stdout_path: Path | None = None, stderr_path: Path | None = None) -> subprocess.CompletedProcess:
    if stdout_path is None or stderr_path is None:
        raise ValueError('bounded output paths are required')
    stdout_path.parent.mkdir(parents=True, exist_ok=True); stderr_path.parent.mkdir(parents=True, exist_ok=True)
    out = stdout_path.open('wb'); err = stderr_path.open('wb')
    process = subprocess.Popen(command, stdout=out, stderr=err, text=False, start_new_session=False)
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill(); process.wait(timeout=5)
        raise
    finally:
        out.close(); err.close()
    stdout = bounded_text(stdout_path)
    stderr = bounded_text(stderr_path)
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)

def logged(command: list[str], prefix: Path, timeout: int = 60) -> subprocess.CompletedProcess:
    stdout_path = prefix.with_suffix('.stdout.txt'); stderr_path = prefix.with_suffix('.stderr.txt')
    try:
        result = run(command, timeout, stdout_path, stderr_path)
    except subprocess.TimeoutExpired as exc:
        stdout = bounded_text(stdout_path) if stdout_path.exists() else ''
        stderr = bounded_text(stderr_path) if stderr_path.exists() else ''
        return subprocess.CompletedProcess(command, 124, stdout, stderr)
    return result

def nonvacuous(raw: dict) -> bool:
    image = raw.get('image', {})
    return raw.get('status') == 'OBSERVED' and image.get('width', 0) > 0 and image.get('height', 0) > 0 and image.get('uniqueByteValues', 0) > 1

def witness_ax_nodes(raw: dict) -> list[dict]:
    """Exclude application/window/chrome; raw AX tree remains preserved regardless."""
    nodes = []
    def walk(node, in_witness=False):
        in_witness = in_witness or node.get('subrole') == 'AXHostingView'
        if in_witness and node.get('role') in {'AXStaticText', 'AXImage', 'AXCheckBox', 'AXTextField', 'AXButton'} and node.get('subrole') not in {'AXCloseButton', 'AXMinimizeButton', 'AXZoomButton', 'AXFullScreenButton'} and (node.get('label') or node.get('value') or node.get('title') or node.get('identifier')) and not (node.get('role') == 'AXButton' and not node.get('identifier') and str(node.get('label', '')).lower() in {'close', 'minimize', 'zoom', 'full screen'}):
            nodes.append(node)
        for child in node.get('children', []): walk(child, in_witness)
    for step in raw.get('steps', []): walk(step.get('tree', {}))
    return nodes

def recorder_preflight(scratch: Path, evidence: Path) -> dict:
    """Signed recorder checks AXIsProcessTrusted before intentionally failed launch."""
    info = {'sourceApp': str(RECORDER), 'permissionRequests': False, 'externalAX': 'HELD'}
    if not RECORDER.exists():
        info['reason'] = 'existing signed recorder unavailable'
        return info
    source_binary = RECORDER / 'Contents/MacOS/F1MacRecord'
    info['sourceBinaryHash'] = digest(source_binary)
    verify = logged(['/usr/bin/codesign', '--verify', '--strict', str(RECORDER)], evidence / 'recorder-codesign-verify')
    identity = logged(['/usr/bin/codesign', '-dv', '--verbose=4', str(RECORDER)], evidence / 'recorder-identity')
    info['identityDetails'] = identity.stderr
    if verify.returncode:
        info['reason'] = 'existing signed recorder codesign verification failed'
        return info
    copied = RECORDER  # installed recorder (fixed path), run in place; never copied to a new folder (rule 2026-10-17)
    executable = copied / 'Contents/MacOS/F1MacRecord'
    info['copiedExecutable'] = str(executable)
    info['copiedBinaryHash'] = digest(executable)
    verify_copy = logged(['/usr/bin/codesign', '--verify', '--strict', str(copied)], evidence / 'recorder-copy-verify')
    if verify_copy.returncode:
        info['reason'] = 'installed recorder (fixed path) verification failed'
        return info
    missing = scratch / 'intentionally-nonexistent-preflight-fixture'
    if missing.exists(): raise CaptureError('preflight fixture must not exist')
    steps = scratch / 'recorder-preflight-steps.json'
    write(steps, {'launchArgs': [], 'steps': []})
    result = logged([str(executable), '--fixture', str(missing), '--events', str(scratch / 'preflight-events.jsonl'), '--out', str(scratch / 'preflight-raw.json'), '--steps', str(steps)], evidence / 'recorder-no-prompt-preflight', 10)
    # launch failed means earlier no-prompt AX trust guard succeeded; no real fixture launched.
    trusted = result.returncode == 2 and 'launch failed:' in result.stderr and 'Accessibility permission missing' not in result.stderr
    protocol = logged(['/usr/bin/strings', str(executable)], evidence / 'recorder-binary-protocol', 10)
    generic = '--steps' in protocol.stdout and 'waitNode' in protocol.stdout
    info.update({'axTrusted': trusted, 'externalAX': 'AVAILABLE' if trusted and generic else 'HELD', 'preflightExit': result.returncode, 'preflightMethod': 'AXIsProcessTrusted in unchanged signed recorder, then missing-fixture launch'})
    if not generic: info['reason'] = 'signed binary hard-codes F1 stimuli & lacks generic --steps/launchArgs support; current source is newer than signed binary'
    info['sourceBinaryProtocol'] = 'generic-steps' if generic else 'F1-only'
    info['genericProtocolSupported'] = generic
    if not trusted: info['reason'] = result.stderr.strip()
    return info

def fresh_ax_preflight(scratch: Path, evidence: Path) -> dict:
    source = Path(__file__).with_name('AXClient.swift')
    work = scratch / 'external-ax-client'
    work.mkdir(parents=True, exist_ok=True)
    copied = work / 'AXClient.swift'
    copy_bounded(source, copied)
    executable = work / 'f5-ax-client'
    result = logged(['/usr/bin/xcrun', 'swiftc', '-O', '-o', str(executable), str(copied)], evidence / 'fresh-ax-build', 120)
    info = {'sourceHash': digest(source), 'permissionRequests': False, 'externalAX': 'HELD', 'kind': 'fresh-client'}
    if result.returncode: return info
    info.update({'executable': str(executable), 'binaryHash': digest(executable)})
    identity = logged(['/usr/bin/codesign', '-dv', '--verbose=4', str(executable)], evidence / 'fresh-ax-identity')
    info['identityDetails'] = identity.stderr
    result = logged([str(executable), '--preflight'], evidence / 'fresh-ax-preflight')
    if result.returncode == 0:
        info['preflight'] = json.loads(result.stdout)
        if info['preflight'].get('axTrusted') is True: info['externalAX'] = 'AVAILABLE'
    return info

def fresh_ax_capture(executable: Path, binary_hash: str, case_id: str, directory: Path, client: dict, scheme: str, resource_args: list[str] | None = None) -> subprocess.CompletedProcess:
    stdout = (directory / 'owned-window.stdout.txt').open('w')
    events = directory / 'owned-window-events.jsonl'
    process = subprocess.Popen([str(executable), '--window', '--case', case_id, '--scheme', scheme, '--events', str(events)] + (resource_args or []), stdin=subprocess.PIPE, stdout=stdout, stderr=stdout, text=True, start_new_session=False)
    try:
        write(directory / 'owned-window-process.json', {'pid': process.pid, 'executable': str(executable), 'binaryHash': binary_hash, 'windowTitle': 'SwiftRightFactory-' + case_id, 'client': client, 'processGroupOwned': False, 'parentProcessGroup': True, 'retainedProcessHandle': True})
        return logged([client['executable'], '--pid', str(process.pid), '--owner-path', str(executable), '--owner-hash', binary_hash, '--window-title', 'SwiftRightFactory-' + case_id], directory / 'external-ax', 12)
    finally:
        try: process.communicate(input='{"step":"quit"}\n', timeout=3)
        except subprocess.TimeoutExpired:
            process.terminate()
            try: process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
        stdout.close()



def _compiler_snapshot(paths: list[Path]) -> dict:
    return {str(path.name): {'path': str(path), 'sha256': digest(path), 'bytes': path.stat().st_size} for path in paths}

def _safe_drain(process: subprocess.Popen, timeout: int = 5) -> tuple[bytes, bytes, dict]:
    cleanup = {'termSent': False, 'killSent': False, 'groupMissing': False, 'timedOut': False, 'drainTimedOut': False}
    try:
        stdout, stderr = process.communicate(timeout=timeout)
        return stdout, stderr, cleanup
    except subprocess.TimeoutExpired:
        cleanup['timedOut'] = True
        try:
            process.terminate(); cleanup['termSent'] = True
        except ProcessLookupError:
            cleanup['groupMissing'] = True
        try:
            stdout, stderr = process.communicate(timeout=5)
            return stdout, stderr, cleanup
        except subprocess.TimeoutExpired:
            try:
                process.kill(); cleanup['killSent'] = True
            except ProcessLookupError:
                cleanup['groupMissing'] = True
            try:
                stdout, stderr = process.communicate(timeout=5)
                return stdout, stderr, cleanup
            except subprocess.TimeoutExpired:
                cleanup['drainTimedOut'] = True
                return b'', b'', cleanup

def _write_process_receipt(evidence: Path, receipt: dict) -> None:
    try:
        write(evidence / 'compiler-receipt.json', receipt)
    except Exception as error:
        # Durable fallback preserves failure reason even when normal JSON write fails.
        (evidence / 'compiler-receipt.failure.txt').write_text(repr(error) + '\n' + repr(receipt))

def logical_and_real(raw_path: str) -> tuple[Path, Path]:
    logical = Path(raw_path).expanduser()
    return logical, logical.resolve()

def compiler_build(work: Path, evidence: Path, executable: Path) -> tuple[subprocess.CompletedProcess, dict]:
    """Use original xcrun swiftc policy; record owned process & real tool lineage."""
    witness, adapter = work / 'Witness.swift', work / 'CaptureHost.swift'
    before = _compiler_snapshot([witness, adapter])
    resolver = ['/usr/bin/xcrun', '--find', 'swiftc']
    r_start = datetime.now(timezone.utc).isoformat(); resolver_receipt = {'argv': resolver, 'pid': None, 'pgid': None, 'startedAtUtc': r_start, 'endedAtUtc': None, 'exitCode': None, 'stdoutPath': str(evidence / 'swiftc-resolve.stdout.txt'), 'stderrPath': str(evidence / 'swiftc-resolve.stderr.txt'), 'ownedProcessGroup': False, 'parentProcessGroup': True}
    try:
        rp = subprocess.Popen(resolver, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=False, start_new_session=False); resolver_receipt['pid'] = rp.pid; resolver_receipt['pgid'] = os.getpgrp()
        rout, rerr, cleanup = _safe_drain(rp, 30); resolver_receipt['cleanup'] = cleanup; resolver_receipt['exitCode'] = rp.returncode
    except Exception as error:
        rout, rerr = b'', repr(error).encode(); resolver_receipt['error'] = repr(error); cleanup = {'groupMissing': False, 'termSent': False, 'killSent': False, 'drainTimedOut': False}
    resolver_receipt['endedAtUtc'] = datetime.now(timezone.utc).isoformat(); (evidence / 'swiftc-resolve.stdout.txt').write_bytes(rout); (evidence / 'swiftc-resolve.stderr.txt').write_bytes(rerr); resolver_receipt['stdoutHash'] = digest(evidence / 'swiftc-resolve.stdout.txt'); resolver_receipt['stderrHash'] = digest(evidence / 'swiftc-resolve.stderr.txt')
    if resolver_receipt['exitCode'] != 0 or not rout.strip():
        receipt = {'kind': 'swift-compiler-process-receipt', 'version': '2', 'invocationMode': 'xcrun', 'resolver': resolver_receipt, 'sourceBefore': before, 'sourceAfter': _compiler_snapshot([witness, adapter]), 'sourceDrift': before != _compiler_snapshot([witness, adapter]), 'compiler': None, 'status': 'RESOLVE_FAILED'}; _write_process_receipt(evidence, receipt)
        return subprocess.CompletedProcess(resolver, resolver_receipt['exitCode'] or 127, rout.decode(errors='replace'), rerr.decode(errors='replace')), receipt
    logical_path, real_path = logical_and_real(rout.decode(errors='replace').strip().splitlines()[-1])
    tool_before = {'logicalPath': str(logical_path), 'realPath': str(real_path), 'sha256': digest(real_path, 512 * 1024 * 1024), 'bytes': real_path.stat().st_size}
    mode = os.environ.get('SWIFTRIGHT_COMPILER_MODE', 'xcrun')
    args = ['-parse-as-library', '-O', '-o', str(executable), str(witness), str(adapter)]
    command = ['/usr/bin/xcrun', 'swiftc', *args] if mode == 'xcrun' else [str(logical_path), *args]
    started = datetime.now(timezone.utc).isoformat(); compiler_receipt = {'argv': command, 'logicalCompilerName': 'swiftc', 'logicalCompilerPath': str(logical_path), 'realPathBefore': str(real_path), 'realHashBefore': tool_before['sha256'], 'realToolBefore': tool_before, 'pid': None, 'pgid': None, 'startedAtUtc': started, 'endedAtUtc': None, 'exitCode': None, 'timedOut': False, 'ownedProcessGroup': False, 'parentProcessGroup': True, 'cwd': str(work), 'stdoutPath': str(evidence / 'build.stdout.txt'), 'stderrPath': str(evidence / 'build.stderr.txt')}
    try:
        process = subprocess.Popen(command, cwd=str(work), stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=False, start_new_session=False); compiler_receipt['pid'] = process.pid; compiler_receipt['pgid'] = os.getpgrp()
        stdout, stderr, cleanup = _safe_drain(process, 120); compiler_receipt['cleanup'] = cleanup; compiler_receipt['exitCode'] = process.returncode
    except Exception as error:
        stdout, stderr = b'', repr(error).encode(); compiler_receipt['error'] = repr(error); cleanup = {'groupMissing': False, 'termSent': False, 'killSent': False, 'drainTimedOut': False}
    compiler_receipt['endedAtUtc'] = datetime.now(timezone.utc).isoformat(); (evidence / 'build.stdout.txt').write_bytes(stdout); (evidence / 'build.stderr.txt').write_bytes(stderr); compiler_receipt['stdoutHash'] = digest(evidence / 'build.stdout.txt'); compiler_receipt['stderrHash'] = digest(evidence / 'build.stderr.txt'); compiler_receipt['timedOut'] = bool(compiler_receipt['cleanup'].get('timedOut') or compiler_receipt['cleanup'].get('drainTimedOut'))
    after = _compiler_snapshot([witness, adapter]); source_drift = before != after; compiler_receipt['sourceBefore'] = before; compiler_receipt['sourceAfter'] = after; compiler_receipt['sourceDrift'] = source_drift
    tool_after = {'logicalPath': str(logical_path), 'realPath': str(real_path), 'sha256': digest(real_path, 512 * 1024 * 1024), 'bytes': real_path.stat().st_size}; compiler_receipt['realToolAfter'] = tool_after; compiler_receipt['realToolDrift'] = tool_before != tool_after; compiler_receipt['xcrunPath'] = '/usr/bin/xcrun'; compiler_receipt['xcrunHash'] = digest(Path('/usr/bin/xcrun'))
    compiler_receipt['outputBinary'] = {'path': str(executable), 'sha256': digest(executable), 'bytes': executable.stat().st_size} if executable.exists() else None
    status = 'SOURCE_DRIFT' if source_drift else ('TOOL_DRIFT' if compiler_receipt['realToolDrift'] else ('TIMEOUT' if compiler_receipt['timedOut'] else ('SUCCESS' if compiler_receipt['exitCode'] == 0 and compiler_receipt['outputBinary'] else 'FAILED')))
    receipt = {'kind': 'swift-compiler-process-receipt', 'version': '2', 'invocationMode': mode, 'resolver': resolver_receipt, 'sourceBefore': before, 'sourceAfter': after, 'sourceDrift': source_drift, 'compiler': compiler_receipt, 'status': status}; _write_process_receipt(evidence, receipt)
    code = 125 if source_drift or compiler_receipt['realToolDrift'] else (124 if compiler_receipt['timedOut'] else (compiler_receipt['exitCode'] if compiler_receipt['exitCode'] is not None else 127))
    return subprocess.CompletedProcess(command, code, stdout.decode(errors='replace'), stderr.decode(errors='replace')), receipt

def capture(manifest_path: Path, scratch: Path, output: Path, runs: int, recorder: dict, fresh_client: dict | None = None, case_root: Path | None = None, expected_host_hash: str | None = None) -> dict:
    manifest = json.loads(manifest_path.read_text())
    if manifest['block'] not in PILOTS or manifest.get('compileExpectation') != 'success' or manifest.get('executionEligible') is not True:
        raise CaptureError('capture requires positive pilot probe')
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', manifest['witnessType']): raise CaptureError('invalid witness type')
    case_id = manifest['case']['id']
    if not re.fullmatch(r'[a-z][a-z0-9._/-]{1,159}', case_id) or any(part in {'.', '..', ''} for part in case_id.split('/')):
        raise CaptureError('unsafe case id')
    if Path(manifest['sourceFile']).name != manifest['sourceFile'] or not manifest['sourceFile'].endswith('.swift'):
        raise CaptureError('sourceFile must be Swift basename')
    source = manifest_path.parent / manifest['sourceFile']
    if digest(source) != manifest['sourceHash']: raise CaptureError('generated source hash mismatch')
    name = case_id.replace('/', '_')
    work = (scratch / name).resolve()
    if not work.is_relative_to(internal_scratch(scratch)):
        raise CaptureError('work directory escapes internal scratch')
    work.mkdir(parents=True, exist_ok=True)
    evidence = output / name
    if evidence.exists(): raise CaptureError('capture output already exists; preserve independent run evidence')
    evidence.mkdir(parents=True)
    shutil.copy2(source, work / 'Witness.swift')
    harness = Path(__file__).with_name('CaptureHost.swift')
    adapted = harness.read_text().replace('__WITNESS_TYPE__', manifest['witnessType'])
    (work / 'CaptureHost.swift').write_text(adapted)
    executable = work / 'capture-host'
    build, compiler_receipt = compiler_build(work, evidence, executable)
    summary = {'kind': 'macos-host-capture-candidate', 'version': '0.1', 'case': manifest['case'], 'block': manifest['block'], 'probeManifest': manifest, 'sourceHash': digest(source), 'provenance': provenance(source, producer='factory/native/macos'), 'adapterSourceHash': digest(harness), 'compiledAdapterHash': digest(work / 'CaptureHost.swift'), 'executionRoot': str(work), 'candidateOnly': True, 'acceptance': 'not-promoted', 'independentProcessesPerRun': True, 'recorder': recorder, 'freshAXClient': fresh_client, 'compilerReceipt': compiler_receipt, 'runs': [], 'channels': {}}
    if build.returncode:
        summary.update({'status': 'BUILD_FAILED', 'buildExit': build.returncode})
        write(evidence / 'summary.json', summary)
        return summary
    summary['binaryHash'] = digest(executable)
    if expected_host_hash is None:
        raise CaptureError('expected host hash is required before native capture')
    if summary['binaryHash'] != expected_host_hash:
        summary.update({'status': 'HOST_HASH_DRIFT', 'hostHashExpected': expected_host_hash, 'hostHashActual': summary['binaryHash'], 'runs': []})
        write(evidence / 'summary.json', summary)
        return summary
    preflight = logged([str(executable), '--preflight'], evidence / 'fresh-host-preflight')
    summary['permissionCapabilities'] = json.loads(preflight.stdout) if preflight.returncode == 0 else {'error': preflight.stderr}
    inputs = manifest.get('environmentInputs', {})
    # Verify host environment against persisted canonical case; source axes already baked by F4.
    case_file = (case_root or (REPO / 'factory/pipeline/cases')) / (case_id.replace('/', '--') + '.json')
    if not case_file.exists() and case_root:
        case_file = case_root / (case_id.replace('/', '__') + '.json')
    if not case_file.exists(): case_file = REPO / 'factory/recipes/cases' / (name + '.json')
    if not case_file.exists(): raise CaptureError('execution eligible probe requires persisted canonical case')
    if case_file.exists():
        from factory.core.artifacts import canonical_hash
        case = json.loads(case_file.read_text())
        if canonical_hash(case) != manifest['case']['hash']: raise CaptureError('case inputs hash mismatch')
        recipe_file = (REPO / manifest['recipeFile']).resolve() if manifest.get('recipeFile') else REPO / 'factory/recipes/data' / (manifest['block'] + '.json')
        if not recipe_file.is_relative_to(REPO / 'factory'): raise CaptureError('recipe file escapes factory')
        recipe = json.loads(recipe_file.read_text())
        if canonical_hash(recipe) != manifest['recipe']['hash'] or case['recipe'] != manifest['recipe']:
            raise CaptureError('canonical recipe hash mismatch')
        if case['inputs'] != manifest.get('caseInputs'):
            raise CaptureError('manifest axes differ from canonical case')
        inputs = manifest.get('environmentInputs', {})
        case_inputs = case.get('inputs', {})
        if inputs.get('colorScheme', 'light') != case_inputs.get('color-scheme', case_inputs.get('colorScheme', 'light')):
            raise CaptureError('environment color scheme differs from canonical case')
        expected_inputs = {'text': 'Aa', 'font': {'family': 'system', 'size': 24, 'weight': 'regular', 'design': 'default'}, 'foreground': 'primary', 'colorScheme': 'light', 'viewport': {'width': 120, 'height': 48, 'alignment': 'center'}}
        if manifest['block'] == 'swiftui.text.layout.baseline' and case_inputs != expected_inputs:
            raise CaptureError('Text baseline input contract drift')
        if manifest['block'] == 'swiftui.text.layout.baseline' and (inputs.get('font') != expected_inputs['font'] or inputs.get('viewport') != expected_inputs['viewport']):
            raise CaptureError('Text baseline font/viewport contract drift')
    scale = str(manifest.get('caseInputs', {}).get('scale', 1))
    scheme = str(inputs.get('colorScheme', 'light'))
    resource_args = []
    font_resource = manifest.get('providerResources', {}).get('font')
    if font_resource:
        if not any(item.get('hash') == font_resource['hash'] for item in recipe.get('provenance', {}).get('inputs', [])):
            raise CaptureError('font resource hash is not bound by canonical recipe')
        resource = (REPO / font_resource['path']).resolve()
        if not resource.is_relative_to(REPO / 'factory/resources/fonts') or digest(resource) != font_resource['hash']:
            raise CaptureError('font resource path/hash mismatch')
        copied_resource = work / 'private-font.ttf'
        shutil.copy2(resource, copied_resource)
        if digest(copied_resource) != font_resource['hash']: raise CaptureError('copied font hash mismatch')
        resource_args = ['--font-resource', str(copied_resource), '--font-hash', font_resource['hash'], '--font-postscript', font_resource['postScriptName']]
        summary['fontResource'] = {**font_resource, 'copiedPath': str(copied_resource), 'copiedHash': digest(copied_resource), 'scope': 'process'}
    for index in range(1, runs + 1):
        directory = evidence / f'run-{index:03d}'
        directory.mkdir()
        row = {'run': index, 'offscreen': 'HELD', 'externalAX': 'HELD', 'compositorPaint': 'HELD'}
        for mode in ('plain', 'instrumented'):
            png = directory / f'{mode}.png'
            arguments = [str(executable), '--png', str(png), '--scale', scale, '--scheme', scheme] + resource_args
            if mode == 'plain': arguments.append('--plain')
            result = logged(arguments, directory / mode)
            if result.returncode != 0:
                row[mode] = {'status': 'FAILED', 'exit': result.returncode}
                continue
            raw = json.loads(result.stdout)
            write(directory / f'{mode}.raw.json', raw)
            row[mode] = {'status': 'OBSERVED' if nonvacuous(raw) else 'UNOBSERVED', 'rawHash': digest(directory / f'{mode}.raw.json'), 'pngHash': digest(png), 'pid': raw['pid'], 'image': raw['image'], 'rootLayoutCallbacks': len(raw['rootLayout']['placements']), 'textRendererRuns': len(raw['textRendererRuns'])}
        if row.get('plain', {}).get('status') == 'OBSERVED' and row.get('instrumented', {}).get('status') == 'OBSERVED':
            row['offscreen'] = 'OBSERVED'
            row['instrumentationPixelsEqual'] = row['plain']['pngHash'] == row['instrumented']['pngHash']
        if summary['permissionCapabilities'].get('screenCaptureGranted') is True:
            compositor_png = directory / 'compositor.png'
            result = logged([str(executable), '--window', '--compositor', '--case', manifest['case']['id'], '--scheme', scheme, '--png', str(compositor_png)] + resource_args, directory / 'compositor', 20)
            if result.returncode == 0:
                raw = json.loads(result.stdout)
                write(directory / 'compositor.raw.json', raw)
                row['compositorPaint'] = 'OBSERVED' if nonvacuous(raw) and row['offscreen'] == 'OBSERVED' else 'HELD'
                row['compositorScope'] = 'owned window including chrome; witness render corroborated by nonvacuous offscreen capture'
                row['compositorRawHash'] = digest(directory / 'compositor.raw.json')
                metrics = raw.get('witnessHostMetrics', {})
                fitting = metrics.get('fittingSizePoints', {})
                row['rootHostGeometry'] = 'OBSERVED' if fitting.get('width', 0) > 0 and fitting.get('height', 0) > 0 else 'HELD'
                if compositor_png.exists(): row['compositorPngHash'] = digest(compositor_png)
            else: row['compositorReason'] = f'owned capture host exit {result.returncode}'
        if fresh_client and fresh_client.get('externalAX') == 'AVAILABLE':
            result = fresh_ax_capture(executable, summary['binaryHash'], case_id, directory, fresh_client, scheme, resource_args)
            if result.returncode == 0:
                raw = json.loads(result.stdout)
                write(directory / 'external-ax.raw.json', raw)
                count = len(witness_ax_nodes(raw))
                row['externalAX'] = 'OBSERVED' if count else 'HELD'
                row['externalAXWitnessNodes'] = count
                row['externalAXRawHash'] = digest(directory / 'external-ax.raw.json')
                row['externalAXClientHash'] = fresh_client['binaryHash']
                if count and (directory / 'compositor.raw.json').exists() and nonvacuous(json.loads((directory / 'compositor.raw.json').read_text())):
                    row['compositorPaint'] = 'OBSERVED'
                    row['compositorScope'] = 'owned window including chrome; witness corroborated by external AXHostingView nodes'
                if not count: row['externalAXReason'] = raw.get('reason', 'chrome-only external tree rejected')
            else: row['externalAXReason'] = f'fresh owned AX client exit {result.returncode}'
        elif recorder.get('externalAX') == 'AVAILABLE':
            plan = directory / 'recorder-steps.json'
            write(plan, {'launchArgs': ['--window', '--case', manifest['case']['id'], '--scheme', scheme], 'steps': [{'id': 'snapshot', 'logicalAction': 'observe-static-witness', 'settleMs': 250, 'ops': []}]})
            raw_path = directory / 'external-ax.raw.json'
            result = logged([recorder['copiedExecutable'], '--fixture', str(executable), '--events', str(directory / 'window-events.jsonl'), '--out', str(raw_path), '--steps', str(plan)], directory / 'external-ax', 35)
            if result.returncode == 0 and raw_path.exists():
                ax = json.loads(raw_path.read_text())
                count = len(witness_ax_nodes(ax))
                row['externalAX'] = 'OBSERVED' if count else 'HELD'
                row['externalAXWitnessNodes'] = count
                row['externalAXRawHash'] = digest(raw_path)
                if not count: row['externalAXReason'] = 'external tree contains no labelled witness nodes; chrome-only tree rejected'
            else:
                row['externalAXReason'] = f'recorder exit {result.returncode}'
        summary['runs'].append(row)
        write(evidence / 'summary.json', summary)
        print(f'{name} run {index}/{runs}: {row["offscreen"]} AX={row["externalAX"]}', flush=True)
    offscreen_complete = len(summary['runs']) == runs and all(row['offscreen'] == 'OBSERVED' for row in summary['runs'])
    complete = len(summary['runs']) == runs and all(any(row[channel] == 'OBSERVED' for channel in ('offscreen', 'compositorPaint', 'externalAX')) for row in summary['runs'])
    summary['status'] = 'CANDIDATE_CAPTURED' if complete else 'INCOMPLETE'
    summary['channels'] = {'offscreenPaint': 'OBSERVED' if offscreen_complete else 'HELD', 'rootLayout': 'OBSERVED' if all(row.get('instrumented', {}).get('rootLayoutCallbacks', 0) > 0 for row in summary['runs']) else 'HELD', 'textRenderer': 'OBSERVED' if all(row.get('instrumented', {}).get('textRendererRuns', 0) > 0 for row in summary['runs']) else 'NOT_APPLICABLE_OR_HELD', 'externalAX': 'OBSERVED' if all(row['externalAX'] == 'OBSERVED' for row in summary['runs']) else 'HELD', 'compositorPaint': 'OBSERVED' if all(row['compositorPaint'] == 'OBSERVED' for row in summary['runs']) else 'HELD', 'witnessInternalLayoutCallbacks': 'HELD: root adapter does not instrument witness internal Layout', 'witnessFontResolution': 'HELD: TextRenderer does not expose resolved font; CoreText control kept separate', 'animation': 'NOT_ATTEMPTED: static pilot', 'events': 'OBSERVED: render clock & host window display only'}
    summary['channels']['rootHostGeometry'] = 'OBSERVED: actual NSHostingView fitting size/bounds, not internal Layout callbacks' if all(row.get('rootHostGeometry') == 'OBSERVED' for row in summary['runs']) else 'HELD'
    if font_resource:
        font_observed = all(json.loads((evidence / f'run-{row["run"]:03d}' / 'instrumented.raw.json').read_text()).get('registeredFontResource', {}).get('resourceHash') == font_resource['hash'] for row in summary['runs'])
        summary['channels']['registeredFontProvider'] = 'OBSERVED: hash-bound process CoreText font descriptor identity' if font_observed else 'HELD'
    from factory.native.macos.normalize import normalize_run
    for row in summary['runs']:
        if (evidence / f'run-{row["run"]:03d}' / 'instrumented.raw.json').exists():
            directory = evidence / f'run-{row["run"]:03d}'
            normalize_run(directory, manifest, case, row['run'], summary['channels'], summary['binaryHash'])
            row['captureHash'] = digest(directory / 'capture.json')
    write(evidence / 'summary.json', summary)
    return summary

def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, action='append', required=True)
    parser.add_argument('--scratch', type=Path, default=DEFAULT_SCRATCH)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--runs', type=int, default=20)
    parser.add_argument('--case-root', type=Path, help='canonical case directory; every case/recipe hash still verified')
    parser.add_argument('--expected-host-hash', required=True, help='sha256 of separately preflighted internal capture host; drift aborts before native launch')
    options = parser.parse_args(argv)
    if options.runs < 1: parser.error('--runs must be positive')
    scratch = internal_scratch(options.scratch)
    scratch.mkdir(parents=True, exist_ok=True)
    options.output.mkdir(parents=True, exist_ok=True)
    recorder = recorder_preflight(scratch, options.output)
    write(options.output / 'recorder-capabilities.json', recorder)
    fresh_client = fresh_ax_preflight(scratch, options.output)
    write(options.output / 'fresh-ax-client.json', fresh_client)
    results = [capture(path, scratch, options.output, options.runs, recorder, fresh_client, options.case_root, options.expected_host_hash) for path in options.manifest]
    write(options.output / 'capture-index.json', {'createdAt': datetime.now(timezone.utc).isoformat(), 'candidateOnly': True, 'results': [{'case': item['case'], 'status': item['status'], 'channels': item['channels']} for item in results]})
    return 0 if all(item['status'] == 'CANDIDATE_CAPTURED' for item in results) else 1

if __name__ == '__main__':
    try: raise SystemExit(main())
    except (CaptureError, OSError, ValueError, KeyError) as error:
        print(f'F5 capture: {error}', file=sys.stderr)
        raise SystemExit(2)
