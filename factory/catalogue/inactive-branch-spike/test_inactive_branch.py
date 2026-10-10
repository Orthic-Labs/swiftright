#!/usr/bin/env python3
import json
import tempfile
from pathlib import Path
from exact_inactive_validator import Validator, HERE, digest, require


def main():
    payload = json.loads((HERE/'inactive-branch-evidence.json').read_text())
    require(payload['version'] == 2 and payload['resolution'] == Validator().validate(), 'serialized resolution differs from independent reconstruction')
    require(len(payload['controls']) >= 60 and all(c['baselineAccepted'] and c['bytesDiffer'] and c['rejected'] and c['beforeSha256'] != c['afterSha256'] for c in payload['controls']), 'invalid raw control coverage')
    for descriptor in payload['inputs'].values():
        require(digest(Path(descriptor['path']).read_bytes()) == descriptor['sha256'], 'serialized provenance byte pin mismatch')
    from investigate_inactive_branch import run
    with tempfile.TemporaryDirectory(prefix='inactive-branch-replay-') as directory:
        require(run(Path(directory)/'replayed.json') == payload, 'whole artifact differs from fresh actual compiler/raw fault replay')
    print('inactive production replay passed: exact single row & ' + str(len(payload['controls'])) + ' raw faults')


if __name__ == '__main__':main()
