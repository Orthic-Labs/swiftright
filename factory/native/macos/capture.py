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
from datetime import datetime, timezone

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO))
if not __import__('importlib.util', fromlist=['find_spec']).find_spec('jsonschema'):
    for packages in (REPO / 'factory/.venv/lib').glob('python*/site-packages'):
        sys.path.insert(0, str(packages))
from factory.core.artifacts import file_hash, provenance

DEFAULT_SCRATCH = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1')
PILOTS = ('swiftui.shapes.fill-stroke', 'swiftui.image', 'swiftui.stack-overlay', 'swiftui.text.bundled-font', 'swiftui.custom-layout', 'swiftui.scroll-view', 'swiftui.toggle', 'swiftui.disabled', 'swiftui.padding-frame', 'swiftui.preference-key')
RECORDER = REPO / 'probes/sr0-o/f1-cross/out/signed/F1MacRecord.app'

class CaptureError(ValueError): pass

def digest(path: Path) -> str:
    return file_hash(path)

def write(path: Path, obj: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, sort_keys=True, indent=2) + '\n')

def internal_scratch(path: Path) -> Path:
    path = path.expanduser().resolve()
    allowed = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory').resolve()
    if not path.is_relative_to(allowed) or path == allowed:
        raise CaptureError('scratch must be child of internal SwiftRightFactory cache')
    return path

def run(command: list[str], timeout: int = 60) -> subprocess.CompletedProcess:
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        # Only this newly owned process group; fixture inherits recorder group.
        os.killpg(process.pid, signal.SIGTERM)
        try: process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
        raise
    return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)

def logged(command: list[str], prefix: Path, timeout: int = 60) -> subprocess.CompletedProcess:
    try:
        result = run(command, timeout)
    except subprocess.TimeoutExpired as exc:
        prefix.with_suffix('.stdout.txt').write_text((exc.stdout or b'').decode() if isinstance(exc.stdout, bytes) else exc.stdout or '')
        prefix.with_suffix('.stderr.txt').write_text((exc.stderr or b'').decode() if isinstance(exc.stderr, bytes) else exc.stderr or '')
        return subprocess.CompletedProcess(command, 124, (exc.stdout or b'').decode() if isinstance(exc.stdout, bytes) else exc.stdout or '', (exc.stderr or b'').decode() if isinstance(exc.stderr, bytes) else exc.stderr or '')
    prefix.with_suffix('.stdout.txt').write_text(result.stdout)
    prefix.with_suffix('.stderr.txt').write_text(result.stderr)
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
    copied = scratch / 'existing-recorder/F1MacRecord.app'
    if copied.exists():
        if digest(copied / 'Contents/MacOS/F1MacRecord') != info['sourceBinaryHash']:
            raise CaptureError('existing scratch recorder differs; refusing replacement')
    else:
        copied.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(RECORDER, copied, symlinks=True)
    executable = copied / 'Contents/MacOS/F1MacRecord'
    info['copiedExecutable'] = str(executable)
    info['copiedBinaryHash'] = digest(executable)
    verify_copy = logged(['/usr/bin/codesign', '--verify', '--strict', str(copied)], evidence / 'recorder-copy-verify')
    if verify_copy.returncode:
        info['reason'] = 'scratch copy verification failed'
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
    copied.write_bytes(source.read_bytes())
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
    process = subprocess.Popen([str(executable), '--window', '--case', case_id, '--scheme', scheme, '--events', str(events)] + (resource_args or []), stdin=subprocess.PIPE, stdout=stdout, stderr=stdout, text=True, start_new_session=True)
    try:
        write(directory / 'owned-window-process.json', {'pid': process.pid, 'executable': str(executable), 'binaryHash': binary_hash, 'windowTitle': 'SwiftRightFactory-' + case_id, 'client': client, 'processGroupOwned': True})
        return logged([client['executable'], '--pid', str(process.pid), '--owner-path', str(executable), '--owner-hash', binary_hash, '--window-title', 'SwiftRightFactory-' + case_id], directory / 'external-ax', 12)
    finally:
        try: process.communicate(input='{"step":"quit"}\n', timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGTERM)
            try: process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
        stdout.close()


def capture(manifest_path: Path, scratch: Path, output: Path, runs: int, recorder: dict, fresh_client: dict | None = None, case_root: Path | None = None) -> dict:
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
    build = logged(['/usr/bin/xcrun', 'swiftc', '-parse-as-library', '-O', '-o', str(executable), str(work / 'Witness.swift'), str(work / 'CaptureHost.swift')], evidence / 'build', 120)
    summary = {'kind': 'macos-host-capture-candidate', 'version': '0.1', 'case': manifest['case'], 'block': manifest['block'], 'probeManifest': manifest, 'sourceHash': digest(source), 'provenance': provenance(source, producer='factory/native/macos'), 'adapterSourceHash': digest(harness), 'compiledAdapterHash': digest(work / 'CaptureHost.swift'), 'executionRoot': str(work), 'candidateOnly': True, 'acceptance': 'not-promoted', 'independentProcessesPerRun': True, 'recorder': recorder, 'freshAXClient': fresh_client, 'runs': [], 'channels': {}}
    if build.returncode:
        summary.update({'status': 'BUILD_FAILED', 'buildExit': build.returncode})
        write(evidence / 'summary.json', summary)
        return summary
    summary['binaryHash'] = digest(executable)
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
    options = parser.parse_args(argv)
    if options.runs < 1: parser.error('--runs must be positive')
    scratch = internal_scratch(options.scratch)
    scratch.mkdir(parents=True, exist_ok=True)
    options.output.mkdir(parents=True, exist_ok=True)
    recorder = recorder_preflight(scratch, options.output)
    write(options.output / 'recorder-capabilities.json', recorder)
    fresh_client = fresh_ax_preflight(scratch, options.output)
    write(options.output / 'fresh-ax-client.json', fresh_client)
    results = [capture(path, scratch, options.output, options.runs, recorder, fresh_client, options.case_root) for path in options.manifest]
    write(options.output / 'capture-index.json', {'createdAt': datetime.now(timezone.utc).isoformat(), 'candidateOnly': True, 'results': [{'case': item['case'], 'status': item['status'], 'channels': item['channels']} for item in results]})
    return 0 if all(item['status'] == 'CANDIDATE_CAPTURED' for item in results) else 1

if __name__ == '__main__':
    try: raise SystemExit(main())
    except (CaptureError, OSError, ValueError, KeyError) as error:
        print(f'F5 capture: {error}', file=sys.stderr)
        raise SystemExit(2)
