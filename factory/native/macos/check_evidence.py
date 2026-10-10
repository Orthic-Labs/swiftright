"""Verify F5 source/raw/image/capture hashes & independent process evidence."""
from pathlib import Path
import json
from factory.native.macos.capture import digest
from factory.core.artifacts import validate_artifact

def verify(root: Path) -> dict:
    cases = []
    for summary_file in sorted(root.glob('*/summary.json')):
        summary = json.loads(summary_file.read_text())
        directory = summary_file.parent
        pids = {'plain': set(), 'instrumented': set(), 'compositor': set(), 'externalAX': set()}
        for row in summary['runs']:
            run = directory / f'run-{row["run"]:03d}'
            capture_file = run / 'capture.json'
            capture = json.loads(capture_file.read_text())
            validate_artifact(capture)
            assert digest(capture_file) == row['captureHash']
            assert capture['case'] == summary['case']
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
