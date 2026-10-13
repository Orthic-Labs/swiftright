"""Refresh explicit source/report pins from bounded current bytes; no native actions."""
from pathlib import Path
import hashlib
import json

repo = Path('/Volumes/D/claude/swiftright')
root = repo/'factory/pipeline/pilot-next-source-v1/text-production-reader-root-v1'
manifest = root/'source-manifest.json'
assert manifest.stat().st_size <= 65536
doc = json.loads(manifest.read_text())
def measure(p):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size <= 8388608
    h = hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda: f.read(1048576), b''):
            h.update(b)
    return p.stat().st_size, 'sha256:'+h.hexdigest()
for row in doc['files']:
    row['bytes'], row['sha256'] = measure(root/row['path'])
doc['inputs']['macReportBytes'], doc['inputs']['macReportSha256'] = measure(repo/doc['inputs']['macReport'])
doc['inputs']['productionGateSha256'] = measure(repo/doc['inputs']['productionGate'])[1]
doc['inputs']['compileContractTestsSha256'] = measure(repo/doc['inputs']['compileContractTests'])[1]
doc['inputs']['pairedReportControlsSha256'] = measure(repo/doc['inputs']['pairedReportControls'])[1]
doc['status'] = 'root-reader-controls-r12-pass-native-parity-held'
doc['actualControls'] = {'path':'actual-reader-controls-r12.json','sha256':measure(root/'actual-reader-controls-r12.json')[1],'accepted':20,'faultControls':6,'qualified':False}
manifest.write_text(json.dumps(doc,indent=2)+'\n')
print(json.dumps({'manifest':str(manifest),'sha256':measure(manifest)[1],'nativeActions':0}))
