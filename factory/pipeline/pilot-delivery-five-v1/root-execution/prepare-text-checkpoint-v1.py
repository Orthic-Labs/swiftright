from pathlib import Path
import hashlib
import json
import shutil
import time

repo=Path('/Volumes/D/claude/swiftright')
cache=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root')
root=repo/'factory/pipeline/pilot-next-source-v1/text-production-reader-root-v1'
for src,name in [
 (repo/'.factory-work/root-logs/text-production-reader-controls-r12/receipt.json','reader-controls-r12-supervision.json'),
 (repo/'.factory-work/text-production-reader-paired-controls-r1/paired-report-controls.json','actual-paired-report-controls-r1.json'),
]:
    assert src.is_file() and not src.is_symlink() and src.stat().st_size<=1048576
    dest=root/name
    assert not dest.exists()
    shutil.copyfile(src,dest)
roots=[
 repo/'factory/oracle/mac/text-origin-r11-root-v1/exit-proof-replay-v1',
 repo/'factory/pipeline/pilot-next-source-v1/paired-text-exit-proof-root-v1',
 root,
]
paths=[];total=0;started=time.monotonic()
for scoped in roots:
    assert scoped.is_dir() and not scoped.is_symlink()
    for p in scoped.rglob('*'):
        assert not p.is_symlink()
        if not p.is_file():continue
        assert p.stat().st_size<=8388608
        total+=p.stat().st_size;paths.append(p)
        assert total<=16777216 and len(paths)<=1600 and time.monotonic()-started<45
paths.extend(repo/s for s in [
 'docs/sr0-sr1-running-holds.md',
 'factory/gate/windows_exit_admission.py',
 'factory/tests/test_windows_compile_request.py',
 'factory/pipeline/paired-rectangle-fixed-r11-root-v3/f10-reader-r2/reader-controls-regression-r3.json',
])
files={}
for p in paths:
    assert p.stat().st_size<=8388608 and not p.is_symlink()
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    files[str(p.relative_to(repo))]=h.hexdigest()
assert sum(p.stat().st_size for p in paths)<=16777216
spec=cache/'text-paired-admission-r12-checkpoint-spec.json'
assert not spec.exists()
spec.write_text(json.dumps({'title':'Qualify Text archive admission with fresh paired exit evidence','files':files},indent=2)+'\n')
print(json.dumps({'spec':str(spec),'paths':len(files),'bytes':sum(p.stat().st_size for p in paths),'nativeActions':0}))
