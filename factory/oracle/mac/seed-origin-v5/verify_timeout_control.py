#!/usr/bin/env python3
"""Offline verifier for v5 bounded timeout fault receipt."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path

def digest(path: Path) -> str: return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()
def fail(message: str) -> None: raise ValueError(message)
def validate(root: Path) -> dict:
    root = root.resolve(); receipt = json.loads((root/'fault-controls/timeout/timeout-receipt.json').read_text())
    receipt['status'] == 'TIMEOUT' and receipt['attempts'] == 1 or fail('timeout status/attempts')
    receipt['timedOut'] is True and receipt['cleanup']['timedOut'] is True or fail('initial timeout not retained')
    receipt['cleanup']['termSent'] is True or fail('TERM missing')
    isinstance(receipt['pid'], int) and receipt['pid'] > 0 and receipt['pgid'] == receipt['pid'] or fail('owned pid/group')
    receipt['exitCode'] is not None or fail('missing post-cleanup exit')
    for path_key, hash_key in [('stdoutPath','stdoutHash'),('stderrPath','stderrHash')]:
        p=Path(receipt[path_key]); p.is_file() and digest(p)==receipt[hash_key] or fail(f'raw stream {path_key}')
    summary=json.loads((root/'fault-controls/timeout/control-summary.json').read_text())
    summary['initialTimeoutRecorded'] is True and summary['timedOut'] is True or fail('summary timeout')
    return {'status':'PASS','attempts':1,'timedOut':True,'initialTimeoutRecorded':True,'termSent':receipt['cleanup']['termSent'],'killSent':receipt['cleanup']['killSent'],'exitCode':receipt['exitCode']}
if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('root',type=Path); args=parser.parse_args()
    try: print(json.dumps(validate(args.root),sort_keys=True,indent=2))
    except Exception as error: print(f'FAIL: {error}'); raise SystemExit(1)
