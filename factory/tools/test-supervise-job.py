#!/usr/bin/env python3
"""Real process controls for supervisor deadline, RSS, output & descendant cleanup."""
import argparse
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    tool = Path(__file__).with_name('supervise-job.py')
    cases = [
        ('positive', 5, 128, 1, "print('ok')", 0, None),
        ('deadline', 1, 128, 1, 'import time; time.sleep(30)', 124, 'wall-time-budget'),
        ('rss', 5, 24, 1, 'import time; block=bytearray(48*1024*1024); time.sleep(30)', 124, 'rss-budget'),
        ('output', 5, 128, 1, 'import os; os.write(1,b"x"*(2*1024*1024))', 124, 'log-budget'),
        ('descendant', 5, 128, 1,
         'import subprocess,sys; subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"])',
         0, None),
    ]
    results = []
    for name, seconds, rss, log, source, exit_code, failure in cases:
        dest = args.out / name
        command = [sys.executable, str(tool), '--seconds', str(seconds), '--rss-mib', str(rss),
                   '--log-mib', str(log), '--out', str(dest), '--', sys.executable, '-c', source]
        result = subprocess.run(command, capture_output=True, timeout=15)
        assert len(result.stdout) + len(result.stderr) < 65536
        assert result.returncode == exit_code, (name, result.returncode, result.stderr)
        path = dest / 'receipt.json'
        assert path.stat().st_size < 65536
        receipt = json.loads(path.read_text())
        assert receipt['budgetFailure'] == failure, (name, receipt)
        assert receipt['ownedGroupQuiescent'], (name, receipt)
        results.append({'name': name, 'exitCode': result.returncode, 'budgetFailure': failure,
                        'peakGroupRssBytes': receipt['peakGroupRssBytes'], 'ownedGroupQuiescent': True})
    summary = {'kind': 'factory-supervisor-real-process-controls-v1', 'status': 'passed',
               'controls': results, 'nativeRuns': 0, 'remoteActions': 0}
    (args.out / 'controls.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(json.dumps(summary))


if __name__ == '__main__':
    main()
