"""Archive bounded raw SR0 files; identity guard accepts a CSV up to 2 MiB."""
from pathlib import Path
import base64
import hashlib
import json
import sys

source, output = map(Path, sys.argv[1:])
assert source.is_file() and not source.is_symlink() and source.stat().st_size <= 8 * 1024 * 1024
doc = json.loads(source.read_text(encoding='utf-8-sig'))
assert doc['status'] == 'exported' and 0 < len(doc['files']) <= 32 and doc['bytes'] <= 4 * 1024 * 1024
seen, rows, total = set(), [], 0
for row in doc['files']:
    name = row['path']
    assert name not in seen and name not in ('', '.', '..') and not any(c in name for c in '/\\:')
    assert 0 <= row['bytes'] <= 2 * 1024 * 1024 and len(row['base64']) <= 2800000
    raw = base64.b64decode(row['base64'], validate=True)
    assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
    total += len(raw)
    assert total <= 4 * 1024 * 1024
    rows.append({k: v for k, v in row.items() if k != 'base64'})
    seen.add(name)
assert total == doc['bytes']
output.mkdir()
for row in doc['files']:
    with (output / row['path']).open('xb') as stream:
        stream.write(base64.b64decode(row['base64'], validate=True))
proof = {'status': 'verified-raw-bounded-export', 'files': rows, 'bytes': total, 'qualificationClaim': False}
with (output / 'export-verification.json').open('x') as stream:
    stream.write(json.dumps(proof, indent=2) + '\n')
print(json.dumps({'status': proof['status'], 'files': len(rows), 'bytes': total}))
