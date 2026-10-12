"""Build explicit two-source Mac reference internally, under outer supervision."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import time

repo = Path('/Volumes/D/claude/swiftright')
packet = repo/'factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-full-viewport-v1'
oracle = repo/'factory/oracle/mac/rectangle-fixed-r11-root-v1/observed-mac20-v2/swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.73250c091e3660b1/producer-bytes-v1'
scratch = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/rectangle-full-viewport-r1')
scratch.mkdir(exist_ok=False)
out = packet/'build-r1'
out.mkdir(exist_ok=False)

def sha(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size <= 16*1024*1024
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda:stream.read(1024*1024), b''):h.update(chunk)
    return 'sha256:'+h.hexdigest()

sources=[]
for name,source in [('Witness.swift',oracle/'Witness.swift'),('FullViewportHost.swift',packet/'FullViewportHost.swift')]:
    original=sha(source)
    dest=scratch/name
    shutil.copyfile(source,dest)
    assert sha(dest)==original
    sources.append({'path':str(source.relative_to(repo)), 'internalPath':str(dest),
                    'bytes':dest.stat().st_size, 'sha256':original})
assert sources[0]['sha256']=='sha256:5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d'
argv=['/usr/bin/xcrun','swiftc','-parse-as-library','-O','-j','1','-num-threads','1',
      '-module-cache-path',str(scratch/'module-cache'),'-o',str(scratch/'capture-host'),
      str(scratch/'Witness.swift'),str(scratch/'FullViewportHost.swift')]
started=time.monotonic()
with (out/'compiler.stdout.bin').open('xb') as stdout,(out/'compiler.stderr.bin').open('xb') as stderr:
    child=subprocess.Popen(argv,stdout=stdout,stderr=stderr)
    try:code=child.wait(timeout=300)
    except subprocess.TimeoutExpired:
        child.terminate()
        try:child.wait(timeout=5)
        except subprocess.TimeoutExpired:child.kill();child.wait(timeout=5)
        raise
for source in sources:assert sha(Path(source['internalPath']))==source['sha256']
result={'kind':'factory-full-viewport-mac-build-receipt-v1','argv':argv,'sources':sources,
        'originalProcessPid':child.pid,'originalHandleRetained':True,'exitCode':code,
        'seconds':time.monotonic()-started,'frontendThreads':1,'maxJobs':1,
        'nativeActions':0,'qualified':False,
        'stdoutHash':sha(out/'compiler.stdout.bin'),'stderrHash':sha(out/'compiler.stderr.bin')}
if code==0:result['executable']={'path':str(scratch/'capture-host'),'sha256':sha(scratch/'capture-host'),
                              'bytes':(scratch/'capture-host').stat().st_size}
(out/'receipt.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result))
raise SystemExit(code)
