"""Exact source/case gate for a fresh Mac20; no native execution or eligibility mutation."""
import argparse
import hashlib
import json
from pathlib import Path


def verify(rows, case, source_hash):
    if len(rows) != 20 or len({row['path'] for row in rows}) != 20:
        raise ValueError('Exactly twenty distinct raw captures required')
    if {row['run'] for row in rows} != set(range(1, 21)) or any(type(row['run']) is not int for row in rows):
        raise ValueError('Exact integer run set required')
    for row in rows:
        if row['case'] != case or row['sourceHash'] != source_hash:
            raise ValueError('Raw source/case binding mismatch')
    return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--plan', required=True, type=Path)
    parser.add_argument('--mac-root', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError('Fresh gate receipt required')
    plan_bytes = args.plan.read_bytes()
    plan = json.loads(plan_bytes)
    rows = []
    for index in range(1, 21):
        path = args.mac_root / f'run-{index:03d}' / 'capture.json'
        raw = path.read_bytes()
        capture = json.loads(raw)
        rows.append({'path': str(path), 'hash': hashlib.sha256(raw).hexdigest(),
                     'run': capture['meta']['run'], 'case': capture['case'],
                     'sourceHash': capture['provenance']['sourceHash']})
    verify(rows, plan['case'], plan['sourceHash'])
    args.output.write_text(json.dumps({'kind': 'seed-mac20-exact-source-join',
                                     'planHash': hashlib.sha256(plan_bytes).hexdigest(),
                                     'rows': rows, 'sourceJoined': True,
                                     'nativeParity': 'hold', 'planModified': False}, indent=2) + '\n')


if __name__ == '__main__':
    main()
