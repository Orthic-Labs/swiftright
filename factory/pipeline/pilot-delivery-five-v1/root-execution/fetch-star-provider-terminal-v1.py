"""Bounded byte archive recovery; no compiler, native actions, or remote deletion."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ap = argparse.ArgumentParser()
ap.add_argument('--revision', type=int, choices=range(1, 11), required=True)
ap.add_argument('--attempt', type=int, choices=range(1, 5), required=True)
a = ap.parse_args()
repo = Path('/Volumes/D/claude/swiftright')
out = repo / f'factory/pipeline/pilot-delivery-five-v1/root-execution/system-star-provider-terminal-r{a.revision}-a{a.attempt}'
out.mkdir()
base = 'D:/Claude/swiftright/.factory-work/hosts/system-star-fill/'
names = [(f'run-provider-r{a.revision}-transport.json{s}', 'transport.json'+s)
         for s in ('', '.stdout.bin', '.stderr.bin')]
names += [(f'provider-raster-r{a.revision}/{n}', n) for n in
          ('compile-observation.json', 'compile.stdout.bin', 'compile.stderr.bin')]
rows = []
for remote, local in names:
    target = out / local
    r = subprocess.run(['scp', '-q', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=8',
                        'win:'+base+remote, str(target)], timeout=25,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode:
        (out / 'download-failure.json').write_text(json.dumps({'path': remote, 'exitCode': r.returncode,
            'stderr': r.stderr[:8192].decode('utf-8', errors='replace')}, indent=2)+'\n')
        raise RuntimeError('archive recovery download failed: '+remote)
    assert target.is_file() and not target.is_symlink() and target.stat().st_size <= 2097152
    rows.append({'path': local, 'bytes': target.stat().st_size,
                 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()})
outer = json.loads((out/'transport.json').read_text(encoding='utf-8-sig'))
compile = json.loads((out/'compile-observation.json').read_text(encoding='utf-8-sig'))
result = {'kind': 'factory-provider-terminal-byte-recovery-v1', 'revision': a.revision,
          'files': rows, 'outer': outer, 'compile': compile, 'qualified': False,
          'compilerActions': 0, 'nativeActions': 0, 'remoteDeletion': False}
(out/'recovery.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps({'out': str(out), 'outerChildTerminal': outer.get('childTerminal'),
                 'outerExit': outer.get('childExitCode'), 'compileExit': compile.get('exitCode'),
                 'compileJobActive': compile.get('jobActiveCount'),
                 'compileCleanupActive': compile.get('cleanupJobActive')}))
