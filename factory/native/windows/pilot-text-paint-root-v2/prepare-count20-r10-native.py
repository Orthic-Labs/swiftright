"""Bind proven Count20 launcher to hash-verified fresh admission."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent
admission = root / 'actual-admission-count20-r10-r1'
stage = root / 'capture-count20-r10-root-v3-sources'
verified = json.loads((admission / 'export-verification.json').read_text())
assert verified['status'] == 'verified-raw-small-export'
for row in verified['files']:
    raw = (admission / row['path']).read_bytes()
    assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

preflight = json.loads((admission / 'package-preflight.json').read_text(encoding='utf-8-sig'))
source = json.loads((admission / 'source-inputs.json').read_text(encoding='utf-8-sig'))
assert preflight['status'] == 'source-count20-preflight-passed' and preflight['count'] == 20
assert preflight['nativeActions'] == preflight['compilerActions'] == preflight['lockActions'] == 0
source_hash = sha(admission / 'source-inputs.json')
assert preflight['sourceInputsHash'] == source_hash == sha(stage / 'admission/source-inputs.json')
coordinator_hash = sha(stage / 'overlay/coordinator-count20-lifecycle-v1.ps1')
template_hash = sha(admission / 'config-template.json')
text = (root / 'run-count20-r9.ps1').read_text()
for old, new in (
    ('text-mta-r11-count20-r9', 'text-mta-r11-count20-r10'),
    ('count20-r5', 'count20-r10'),
    ('d73e8c79d007939b8add37e6a95c61bf000c698f28acc71b4311d8e695860a46', coordinator_hash),
    ('80c1efb9e923050f97d5b5ea5a033aedbbe5b5ddb1047fb56a480e90731db948', template_hash),
    ('6c335ddead9c023b1faf40bc9e02fb679112f48ec1955934dd28ce4268789c22', source_hash),
):
    assert old in text
    text = text.replace(old, new)
with (root / 'run-count20-r10.ps1').open('x') as f:
    f.write(text)
print(json.dumps(dict(status='reviewed-admission-bound-launcher', sourceHash=source_hash, coordinatorHash=coordinator_hash, templateHash=template_hash, nativeActions=0)))
