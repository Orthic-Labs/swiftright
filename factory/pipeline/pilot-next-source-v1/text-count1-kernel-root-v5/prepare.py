#!/usr/bin/env python3
"""Run pinned Text v4 source stager with one fresh-output collision repair."""
import hashlib
from pathlib import Path

base = Path(__file__).resolve().parent.parent / 'text-count1-r10-kernel-stage-v4/stage_text_count1_r10_v4.py'
assert base.is_file() and not base.is_symlink() and base.stat().st_size == 41619
raw = base.read_bytes()
assert hashlib.sha256(raw).hexdigest() == '50e8ec75b5e99ca266df28192442ce4411ffb468114d0850974509c1fd611cfb'
source = raw.decode('utf-8')
old = '''    p = stage / "overlay" / "test-mta-stage-closure-v1.ps1"
    with p.open("xb") as fh: fh.write(ps.encode("utf-8"))
'''
new = '''    p = stage / "overlay" / "test-mta-stage-closure-v1.ps1"
    # Donor closure control already exists in this fresh explicit copy.
    regular(p, MAX_FILE_BYTES)
    tmp = p.with_name(p.name + ".root-rewrite")
    with tmp.open("xb") as fh: fh.write(ps.encode("utf-8"))
    os.replace(tmp, p)
'''
assert source.count(old) == 1
source = source.replace(old, new)
scope = {'__file__': str(base), '__name__': '__main__'}
exec(compile(source, str(base) + '-root-v5', 'exec'), scope)
