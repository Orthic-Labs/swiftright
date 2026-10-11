"""Verify F5 source/raw/image/capture hashes & independent process evidence."""
from pathlib import Path
import json
from factory.native.macos.capture import digest
from factory.core.artifacts import canonical_hash, validate_artifact
from factory.gate.mac_origin_admission import mac_origin_admission_issues
from factory.pipeline.archive_reader import ArchiveByteReader

def _origin_ref(value, label):
    assert isinstance(value, dict), f'{label}: missing ref'
    assert set(value) == {'path', 'sha256', 'bytes'}, f'{label}: ref shape'
    assert isinstance(value['path'], str) and value['path'].startswith('/'), f'{label}: absolute path'
    assert isinstance(value['sha256'], str) and value['sha256'].startswith('sha256:'), f'{label}: hash'
    assert type(value['bytes']) is int and value['bytes'] >= 0, f'{label}: bytes'
    return value

def _verify_origin(capture, summary, run, reader):
    conditions = capture.get('meta', {}).get('conditions', {})
    origin = conditions.get('macOrigin') if isinstance(conditions, dict) else None
    assert isinstance(origin, dict), f'run {run}: macOrigin missing'
    assert origin.get('version') == '1', f'run {run}: macOrigin version'
    assert origin.get('captureId') == capture['id'], f'run {run}: captureId mismatch'
    summary_ref = _origin_ref(origin.get('summary'), f'run {run}: summary')
    case_ref = _origin_ref(origin.get('case'), f'run {run}: case')
    source_ref = _origin_ref(origin.get('source'), f'run {run}: source')
    adapter_ref = _origin_ref(origin.get('adapter'), f'run {run}: adapter')
    binary_ref = _origin_ref(origin.get('binary'), f'run {run}: binary')
    receipt_ref = _origin_ref(origin.get('compilerReceipt'), f'run {run}: compilerReceipt')
    read = lambda ref, label: reader(capture=capture, reference=ref)
    origin_summary = json.loads(read(summary_ref, 'summary'))
    origin_case = json.loads(read(case_ref, 'case'))
    receipt = json.loads(read(receipt_ref, 'compilerReceipt'))
    assert origin_summary['case'] == summary['case'], f'run {run}: summary case'
    assert capture['case']['hash'] == canonical_hash(origin_case), f'run {run}: case hash'
    assert capture['case']['id'] == origin_case['id'], f'run {run}: case id'
    assert origin_summary['sourceHash'] == source_ref['sha256'], f'run {run}: source join'
    assert origin_summary['compiledAdapterHash'] == adapter_ref['sha256'], f'run {run}: adapter join'
    assert origin_summary['binaryHash'] == binary_ref['sha256'], f'run {run}: binary join'
    assert receipt.get('status') == 'SUCCESS' and receipt.get('sourceDrift') is False, f'run {run}: compiler status'
    compiler = receipt.get('compiler', {})
    output_mode = compiler.get('outputMode')
    assert compiler.get('outputExecutable') is True and type(output_mode) is int and output_mode & 0o111, f'run {run}: output mode'
    assert receipt.get('compiler', {}).get('outputBinary', {}).get('sha256') == binary_ref['sha256'], f'run {run}: receipt binary'
    fresh_ax = origin_summary.get('freshAXClient')
    if isinstance(fresh_ax, dict) and fresh_ax.get('externalAX') == 'AVAILABLE':
        auxiliary = origin.get('auxiliaryAX')
        assert isinstance(auxiliary, dict), f'run {run}: auxiliary AX missing'
        for key in ('receipt', 'source', 'binary'):
            auxiliary_ref = _origin_ref(auxiliary.get(key), f'run {run}: auxiliary {key}')
            read(auxiliary_ref, f'auxiliary {key}')

def verify(root: Path) -> dict:
    cases = []
    for summary_file in sorted(root.glob('*/summary.json')):
        summary = json.loads(summary_file.read_text())
        directory = summary_file.parent
        config_path = directory / 'origin-reader-config.json'
        assert config_path.is_file(), f'origin reader config missing: {directory}'
        config = json.loads(config_path.read_text())
        reader = ArchiveByteReader(mac_roots=config['macRoots'], windows_archives=config.get('windowsArchives', {}), mac_path_map=config['macPathMap'])
        pids = {'plain': set(), 'instrumented': set(), 'compositor': set(), 'externalAX': set()}
        for row in summary['runs']:
            run = directory / f'run-{row["run"]:03d}'
            capture_file = run / 'capture.json'
            capture = json.loads(capture_file.read_text())
            validate_artifact(capture)
            assert digest(capture_file) == row['captureHash']
            assert capture['case'] == summary['case']
            _verify_origin(capture, summary, row['run'], reader)
            issues = mac_origin_admission_issues(capture, lambda ref, item=capture: reader(capture=item, reference=ref))
            assert not issues, f'run {row["run"]}: {issues}'
            for mode in ('plain', 'instrumented'):
                record = row.get(mode, {})
                if record.get('rawHash'):
                    assert digest(run / f'{mode}.raw.json') == record['rawHash']
                    assert digest(run / f'{mode}.png') == record['pngHash']
                    assert record['pid'] not in pids[mode]
                    pids[mode].add(record['pid'])
                    if summary.get('fontResource'):
                        font = json.loads((run / f'{mode}.raw.json').read_text())['registeredFontResource']
                        assert font['resourceHash'] == summary['fontResource']['hash']
                        assert font['postScriptName'] == summary['fontResource']['postScriptName']
                        assert font['fontDescriptorURL'] == summary['fontResource']['copiedPath']
                        assert digest(Path(font['resourcePath'])) == font['resourceHash']
            if (run / 'compositor.raw.json').exists():
                raw = json.loads((run / 'compositor.raw.json').read_text())
                assert raw['pid'] not in pids['compositor']
                pids['compositor'].add(raw['pid'])
                assert digest(run / 'compositor.raw.json') == row['compositorRawHash']
                assert digest(run / 'compositor.png') == row['compositorPngHash']
            if (run / 'external-ax.raw.json').exists():
                raw = json.loads((run / 'external-ax.raw.json').read_text())
                assert raw.get('ownerHash') == summary['binaryHash']
                assert raw['pid'] not in pids['externalAX']
                pids['externalAX'].add(raw['pid'])
                assert digest(run / 'external-ax.raw.json') == row['externalAXRawHash']
        cases.append({'case': summary['case'], 'runs': len(summary['runs']), 'independentPIDs': {key: len(value) for key, value in pids.items()}, 'channels': summary['channels'], 'status': 'PASS'})
    return {'status': 'PASS', 'cases': cases, 'candidateOnly': True}

if __name__ == '__main__':
    import argparse
    from factory.native.macos.capture import write
    parser = argparse.ArgumentParser()
    parser.add_argument('root', type=Path)
    options = parser.parse_args()
    result = verify(options.root)
    write(options.root / 'verification.json', result)
    print(f'PASS: {len(result["cases"])} cases, {sum(case["runs"] for case in result["cases"])} captures')
