#!/usr/bin/env python3
"""F9 actual v4: source-bound Windows native-v5 20-run observations paired with Mac20 archives."""
from __future__ import annotations
import copy, hashlib, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'factory/pipeline/paired-stack-custom-actual-v4'
WIN = ROOT / 'factory/native/windows'
V5 = WIN / 'round1-native-v5'
V5_STACK = V5 / 'repeat-stack-overlay-r1'
V5_CUSTOM = V5 / 'repeat-custom-layout-r1'
MAC_STACK = ROOT / 'factory/native/macos/evidence/20261010-primary-five-r3/swiftui.stack-overlay.recipe_case_aac89c30fbc61515'
MAC_CUSTOM = ROOT / 'factory/native/macos/evidence/20261010-corrected-primary/swiftui.custom-layout.recipe_case_b30ed0b185e8cb29'
PRIOR_V3 = ROOT / 'factory/pipeline/paired-stack-custom-observation-v3'
REVIEW_ROOT = WIN / 'round1-native-v3/independent-review'
STACK_CASE = 'sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0'
STACK_SOURCE = 'sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee'
CUSTOM_CASE = 'sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a'
CUSTOM_SOURCE = 'sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b'
SUCCESS = 'captured-single-observational-uia-printwindow'

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def load(path: Path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def inv(root: Path):
    files = []
    if root.exists():
        for p in sorted((x for x in root.rglob('*') if x.is_file()), key=lambda x: x.relative_to(root).as_posix()):
            files.append({'path': p.relative_to(root).as_posix(), 'bytes': p.stat().st_size, 'sha256': 'sha256:' + sha(p)})
    blob = json.dumps(files, sort_keys=True, separators=(',', ':')).encode()
    return {
        'root': str(root.relative_to(ROOT)), 'exists': root.exists(), 'fileCount': len(files),
        'bytes': sum(x['bytes'] for x in files),
        'inventorySha256': 'sha256:' + hashlib.sha256(blob).hexdigest() if root.exists() else None,
        'files': files,
    }

def mac_archive(root: Path, case: str, source: str, label: str):
    p = root / 'summary.json'
    assert p.exists(), f'{label}: missing summary'
    d = load(p)
    assert d['case']['hash'] == case and d['sourceHash'] == source
    assert d['provenance']['sourceHash'] == source and d['probeManifest']['sourceHash'] == source
    assert len(d.get('runs', [])) == 20 and d.get('acceptance') == 'not-promoted' and d.get('candidateOnly') is True
    return {
        'label': label, 'path': str(root.relative_to(ROOT)), 'summarySha256': 'sha256:' + sha(p),
        'caseHash': case, 'sourceHash': source, 'runs': 20,
        'status': d.get('status'), 'acceptance': d.get('acceptance'), 'candidateOnly': d.get('candidateOnly'),
        'rawInventory': inv(root),
    }

def row_run(root: Path, row, case: str, source: str, batch: dict):
    i = row.get('index')
    run = root / 'replays' / f'run-{i:03d}'
    out = {'index': i, 'run': row.get('run'), 'path': str(run.relative_to(ROOT)), 'rowStatus': row.get('status'), 'valid': False}
    try:
        plan = load(run / 'plan.json'); obs = load(run / 'observation.json'); dispatch = load(run / 'dispatch.json')
        native = load(run / 'native-observation.json'); pixels = load(run / 'native-01/native.pixels.json')
        ui = load(run / 'native-01/native.uia.json'); config = load(run / 'config.json'); capture = load(run / 'native-01/capture-outcome.json')
        assert row.get('run') == f'run-{i:03d}' and row.get('status') == SUCCESS
        assert row.get('dispatchHash') == sha(run / 'dispatch.json')
        assert plan['case']['hash'] == case and plan['sourceHash'] == source
        assert obs['sourceHash'] == source and obs['exeSha256'] == batch['exeHash']
        assert native['case']['hash'] == case and native['sourceHash'] == source and native['exeSha256'] == batch['exeHash']
        assert native['hostValid'] is True and native['exitCode'] == 0
        assert dispatch.get('status') == SUCCESS and load(run / 'task-result.json').get('status') == SUCCESS
        assert config['exeHash'] == batch['exeHash'] and config['compileReceiptHash'] == batch['compileReceiptHash']
        assert capture['sourceHash'] == source and capture['exeHash'] == batch['exeHash']
        assert capture['compileReceiptHash'] == batch['compileReceiptHash'] and capture.get('primaryError') == ''
        assert pixels['width'] == 800 and pixels['height'] == 600 and pixels['dpi'] == 240
        assert pixels['printWindowRepeatStable'] is True
        assert pixels['methodsEqual'] is False and pixels['controlledOcclusionQualification'] is False
        for ref in native.get('files', []):
            q = run / 'native-01' / ref['path']; assert q.exists() and ('sha256:' + sha(q)) == 'sha256:' + ref['sha256'].replace('sha256:', '')
        # observation.files names compile outputs from producer workspace; native.files are closed raw packet refs.
        out.update({
            'valid': True, 'planSha256': 'sha256:' + sha(run / 'plan.json'),
            'observationSha256': 'sha256:' + sha(run / 'observation.json'),
            'nativeObservationSha256': 'sha256:' + sha(run / 'native-observation.json'),
            'pixelsSha256': 'sha256:' + sha(run / 'native-01/native.pixels.json'),
            'uiaSha256': 'sha256:' + sha(run / 'native-01/native.uia.json'),
            'uiaChildren': len(ui.get('children', [])),
            'uiaRootControlType': ui.get('controlType'),
            'printWindowSha256': 'sha256:' + sha(run / 'native-01/native.printwindow.png'),
            'screenSha256': 'sha256:' + sha(run / 'native-01/native.screen.png'),
            'width': pixels['width'], 'height': pixels['height'], 'dpi': pixels['dpi'],
            'ownedExited': obs.get('ownedExited'), 'hostValid': native.get('hostValid'),
        })
    except (AssertionError, KeyError, FileNotFoundError, json.JSONDecodeError) as exc:
        out['reason'] = type(exc).__name__
    return out

def windows_batch(root: Path, label: str, case: str, source: str):
    bpath = root / 'batch.json'
    assert bpath.exists(), f'{label}: batch missing'
    b = load(bpath); rows = b.get('rows', [])
    result = {
        'label': label, 'path': str(root.relative_to(ROOT)), 'caseHash': case, 'sourceHash': source,
        'batchSha256': 'sha256:' + sha(bpath), 'batchStatus': b.get('status'),
        'requested': b.get('requested'), 'attempted': b.get('attempted'), 'rowCount': len(rows),
        'retry': b.get('retry'), 'nativeParity': b.get('nativeParity'),
        'compileReceiptHash': b.get('compileReceiptHash'), 'exeHash': b.get('exeHash'),
        'rows': [], 'rawInventory': inv(root), 'integrityPassed': False,
    }
    errors = []
    if b.get('requested') != 20: errors.append('requested-count')
    if b.get('attempted') != 20: errors.append('attempted-count')
    if len(rows) != 20: errors.append('row-count')
    if b.get('retry') is not False: errors.append('retry-must-be-false')
    if {r.get('index') for r in rows} != set(range(1, 21)): errors.append('row-index-cardinality')
    if len({r.get('index') for r in rows}) != len(rows): errors.append('duplicate-row-index')
    for row in sorted(rows, key=lambda r: (r.get('index') or 0)):
        result['rows'].append(row_run(root, row, case, source, b))
    if any(not r['valid'] for r in result['rows']): errors.append('invalid-run')
    result['successfulRows'] = sum(1 for r in result['rows'] if r['valid'])
    result['errors'] = errors
    result['integrityPassed'] = not errors and result['successfulRows'] == 20
    # Semantic channel is raw only: no interpretation of image/geometry/color.
    if result['rows']:
        result['semantic'] = {
            'uiaChildrenCounts': [r.get('uiaChildren') for r in result['rows']],
            'uiaRootControlType': sorted({r.get('uiaRootControlType') for r in result['rows']}),
            'printWindowRawPresent': all(bool(r.get('printWindowSha256')) for r in result['rows']),
            'screenRawPresent': all(bool(r.get('screenSha256')) for r in result['rows']),
            'pixelDimensions': sorted({(r.get('width'), r.get('height'), r.get('dpi')) for r in result['rows']}),
            'screenRepeatStableRaw': 'raw per-run field retained; not used as qualification',
            'shapeLayout': 'unavailable', 'roleLabelEnabled': 'unavailable',
        }
    else:
        result['semantic'] = {'uiaChildrenCounts': [], 'printWindowRawPresent': False, 'screenRawPresent': False, 'shapeLayout': 'unavailable', 'roleLabelEnabled': 'unavailable'}
    return result

def review_ref(filename: str):
    p = REVIEW_ROOT / filename
    return {'path': str(p.relative_to(ROOT)), 'exists': p.exists(), 'sha256': 'sha256:' + sha(p) if p.exists() else None, 'status': load(p).get('status') if p.exists() else None}

def make_report():
    stack = windows_batch(V5_STACK, 'native-v5-stack-overlay', STACK_CASE, STACK_SOURCE)
    custom = windows_batch(V5_CUSTOM, 'native-v5-custom-layout', CUSTOM_CASE, CUSTOM_SOURCE)
    mac = {'stack': mac_archive(MAC_STACK, STACK_CASE, STACK_SOURCE, 'mac-stack-overlay-20'), 'custom': mac_archive(MAC_CUSTOM, CUSTOM_CASE, CUSTOM_SOURCE, 'mac-custom-layout-20')}
    return {
        'kind': 'f9-paired-stack-custom-actual-v4', 'version': 4, 'candidateOnly': True,
        'actualCapture': {'windowsStack': stack, 'windowsCustom': custom, 'windows20vs20Available': stack['integrityPassed'] and custom['integrityPassed'], 'sourceBound': True},
        'mac20': mac,
        'reviewReceipts': {'stack20': review_ref('v5-repeat-stack-review-v1.json'), 'custom20': review_ref('v5-repeat-custom-review-v1.json'), 'controls': review_ref('actual-v5-controls-review-v1.json')},
        'priorReports': {'v3Path': str(PRIOR_V3.relative_to(ROOT)), 'v3StageManifest': 'sha256:23459282d40f6da7236866f103b2a448cf753b7e9988ca570b5b379893691d75', 'frozen': True},
        'claims': {
            'windowsActual20vs20Available': stack['integrityPassed'] and custom['integrityPassed'],
            'semanticChannels': 'raw UIA child counts plus raw PrintWindow/screen presence only',
            'customWindowsUIAChildren': '0 in every captured run' if custom['integrityPassed'] and set(custom['semantic']['uiaChildrenCounts']) == {0} else 'held',
            'stackWindowsUIAChildren': sorted(set(stack['semantic']['uiaChildrenCounts'])),
            'macCustomExternalAX': 'held in exact Mac20 archive',
            'timing': 'unavailable', 'pixelGeometry': 'raw-only', 'color': 'raw-only',
            'occlusion': 'unavailable', 'focus': 'unavailable', 'nativeDiff': 'unavailable',
            'parity': 'held', 'goldens': 0, 'qualification': 'held',
            'excludedAttempts': 'none; every v5 attempted row retained',
        },
        'controls': {'runner': 'build_report.py --fault-controls', 'required': ['source-hash-mismatch-rejected', 'case-hash-mismatch-rejected', 'batch-count-mismatch-rejected', 'raw-inventory-mismatch-rejected', 'semantic-channel-mutation-rejected', 'forged-qualification-rejected']},
    }

def validate(r):
    assert r['kind'] == 'f9-paired-stack-custom-actual-v4' and r['version'] == 4 and r['candidateOnly'] is True
    assert r['claims']['qualification'] == 'held' and r['claims']['parity'] == 'held' and r['claims']['goldens'] == 0
    assert r['mac20']['stack']['runs'] == 20 and r['mac20']['custom']['runs'] == 20
    for key, case, source, root in [('windowsStack', STACK_CASE, STACK_SOURCE, V5_STACK), ('windowsCustom', CUSTOM_CASE, CUSTOM_SOURCE, V5_CUSTOM)]:
        b = r['actualCapture'][key]
        assert b['caseHash'] == case and b['sourceHash'] == source and b['requested'] == 20 and b['attempted'] == 20
        assert b['rowCount'] == 20 and b['successfulRows'] == 20 and b['integrityPassed'] is True
        assert b['rawInventory'] == inv(root)
        fresh = windows_batch(root, b['label'], case, source)
        assert fresh['rawInventory'] == b['rawInventory'] and fresh['integrityPassed'] is True
        assert b['semantic']['uiaChildrenCounts'] == fresh['semantic']['uiaChildrenCounts']
    assert r['actualCapture']['windows20vs20Available'] is True
    assert r['claims']['windowsActual20vs20Available'] is True
    assert set(r['actualCapture']['windowsCustom']['semantic']['uiaChildrenCounts']) == {0}
    assert r['claims']['customWindowsUIAChildren'] == '0 in every captured run'
    for root_key in ('stack', 'custom'):
        assert r['mac20'][root_key]['rawInventory'] == inv(ROOT / r['mac20'][root_key]['path'])
    return True

def controls(r):
    validate(r); outcomes = {}
    muts = {
        'source-hash-mismatch': lambda q: q['actualCapture']['windowsStack'].__setitem__('sourceHash', 'sha256:' + '0' * 64),
        'case-hash-mismatch': lambda q: q['actualCapture']['windowsCustom'].__setitem__('caseHash', 'sha256:' + '1' * 64),
        'batch-count-mismatch': lambda q: q['actualCapture']['windowsStack'].__setitem__('attempted', 19),
        'raw-inventory-mismatch': lambda q: q['actualCapture']['windowsCustom']['rawInventory']['files'].pop(),
        'semantic-mutation': lambda q: q['actualCapture']['windowsCustom']['semantic']['uiaChildrenCounts'].__setitem__(0, 1),
        'forged-qualification': lambda q: q['claims'].__setitem__('qualification', 'qualified'),
    }
    for name, mutate in muts.items():
        q = copy.deepcopy(r); mutate(q)
        try: validate(q)
        except (AssertionError, KeyError, FileNotFoundError): outcomes[name] = 'rejected'
        else: outcomes[name] = 'accepted-BUG'
    assert all(v == 'rejected' for v in outcomes.values()), outcomes
    return outcomes

def stage_manifest():
    files = []
    for p in sorted(x for x in OUT.iterdir() if x.is_file() and x.name != 'stage-manifest.json'):
        files.append({'path': p.name, 'bytes': p.stat().st_size, 'sha256': 'sha256:' + sha(p)})
    assert all(x['bytes'] < 100 * 1024 * 1024 for x in files)
    return {'kind': 'f9-paired-stack-custom-actual-v4-stage', 'files': files, 'fileCount': len(files), 'totalBytes': sum(x['bytes'] for x in files), 'maxBytes': max((x['bytes'] for x in files), default=0)}

def main():
    report = make_report(); validate(report)
    if '--fault-controls' in sys.argv:
        print(json.dumps({'baseline': 'accepted', 'controls': controls(report)}, indent=2)); return
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'report.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    roots = [V5_STACK, V5_CUSTOM, MAC_STACK, MAC_CUSTOM]
    pins = {'kind': 'f9-v4-raw-input-pins', 'sourceCaseExeBound': True, 'roots': [inv(x) for x in roots]}
    (OUT / 'raw-pins.json').write_text(json.dumps(pins, indent=2, sort_keys=True) + '\n')
    (OUT / 'README.md').write_text('''# Paired stack/custom actual v4\n\nThis candidate consumes native-v5 Windows stack-overlay & custom-layout 20-run batches plus exact Mac20 source/case archives. Every Windows row is retained & source/case/executable/compile/raw-file joined. Custom Windows UIA has zero children in all 20 rows; Mac custom external AX remains held.\n\nThis artifact reports raw observational channels only. Timing, pixel geometry interpretation, color, occlusion qualification, focus, parity, native diff & goldens remain unavailable/held. v3 is referenced as frozen lineage.\n\nRun `PYTHONDONTWRITEBYTECODE=1 python3 build_report.py --fault-controls` for baseline & protected normalization controls.\n''')
    (OUT / 'stage-manifest.json').write_text(json.dumps(stage_manifest(), indent=2, sort_keys=True) + '\n')
    print(json.dumps({'status': 'ok', 'windows20vs20Available': report['claims']['windowsActual20vs20Available'], 'stackRows': report['actualCapture']['windowsStack']['successfulRows'], 'customRows': report['actualCapture']['windowsCustom']['successfulRows'], 'goldens': 0}, indent=2))

if __name__ == '__main__': main()
