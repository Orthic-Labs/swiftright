#!/usr/bin/env python3
"""Replay production validator & verify serialized receipt against reconstruction."""
import json
import tempfile
from pathlib import Path
from exact_validator import HERE, Validator, digest, require


def main():
    payload = json.loads((HERE / 'module-provenance-evidence.json').read_text())
    validator = Validator()
    require(payload['version'] == 2 and payload['rows'] == validator.validate(), 'receipt differs from independent production reconstruction')
    require(payload['resolution']['rows'] == 33 and payload['resolution']['strictBridgePromotion'] == 0, 'unexpected resolution')
    require(len(payload['controls']) == 346, 'raw fault coverage mismatch')
    require(all(c['baselineAcceptedRows'] == 33 and c['bytesDiffer'] and c['rejected'] and c['beforeSha256'] != c['afterSha256'] for c in payload['controls']), 'invalid raw fault receipt')
    for receipt in payload['inputs'].values():
        if isinstance(receipt, dict) and 'path' in receipt and 'sha256' in receipt:
            require(digest(Path(receipt['path']).read_bytes()) == receipt['sha256'], 'receipt byte pin mismatch')
    from investigate_module_provenance import run
    with tempfile.TemporaryDirectory(prefix="module-provenance-replay-") as directory:
        require(payload == run(Path(directory) / "replayed.json"), "serialized receipt differs from complete raw-fault production replay")
    # Receipt name/line/USR edits are separately rejected by reconstruction equality.
    print('module production replay passed: 33 rows, 6 exact origins & 346 raw faults')


if __name__ == '__main__':
    main()
