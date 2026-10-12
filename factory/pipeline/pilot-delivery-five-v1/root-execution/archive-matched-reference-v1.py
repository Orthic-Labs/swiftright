"""Archive one genuine full-viewport Mac observation & original exit evidence."""
import hashlib
import json
from pathlib import Path
import shutil
import argparse
ap=argparse.ArgumentParser()
ap.add_argument("--host",choices=("rounded-stroke","custom-layout","stack-overlay"),required=True)
a=ap.parse_args()

repo=Path('/Volumes/D/claude/swiftright')
packet=repo/f'factory/pipeline/pilot-delivery-five-v1/root-execution/{a.host}-full-viewport-v1'
log_host='rounded' if a.host=='rounded-stroke' else a.host
logs=repo/f'.factory-work/root-logs/{log_host}-full-viewport-mac-count1-r1'
out=packet/'observed-count1-r1'
out.mkdir(exist_ok=False)

def read(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=4*1024*1024
    return path.read_bytes()
def hash_bytes(data):return 'sha256:'+hashlib.sha256(data).hexdigest()

observation=json.loads(read(logs/'stdout.bin'))
supervision=json.loads(read(logs/'receipt.json'))
start=json.loads(read(logs/'start.json'))
build=json.loads(read(packet/'build-r1/receipt.json'))
assert supervision['exitCode']==0 and supervision['budgetFailure'] is None
assert supervision['ownedGroupQuiescent'] is True and supervision['quiescenceKnown'] is True
assert observation['pid']==start['pid']==supervision['pid']
assert observation['status']=='OBSERVED' and observation['captureScale']==2.5
assert observation['viewportPoints']==[320,240] and observation['imagePixels']==[800,600]
assert observation['hostBoundsPoints']=={'x':0,'y':0,'width':320,'height':240}
assert not observation['permissionRequests'] and not observation['screenCaptureAttempted']
assert start['argv'][0]==build['executable']['path']
binary=Path(build['executable']['path'])
assert hash_bytes(read(binary))==build['executable']['sha256']
rows=[]
for source,name in [(Path(observation['pngPath']),'client.png'),
                    (logs/'stdout.bin','observation.raw.json'),(logs/'stderr.bin','stderr.bin'),
                    (logs/'receipt.json','supervision.json'),(logs/'start.json','original-start.json')]:
    data=read(source)
    if source.parent==logs and source.name in ('stdout.bin','stderr.bin'):
        key='stdout' if source.name=='stdout.bin' else 'stderr'
        assert supervision[key]['bytes']==len(data)
        assert 'sha256:'+supervision[key]['sha256']==hash_bytes(data)
    with (out/name).open('xb') as stream:stream.write(data)
    assert hash_bytes(read(out/name))==hash_bytes(data)
    rows.append({'path':name,'bytes':len(data),'sha256':hash_bytes(data)})
manifest={'kind':'factory-full-viewport-mac-count1-archive-v1','rows':rows,
          'sourceHash':build['sources'][0]['sha256'],'hostSourceHash':build['sources'][1]['sha256'],
          'hostHash':build['executable']['sha256'],'buildReceiptPath':str((packet/'build-r1/receipt.json').relative_to(repo)),
          'captureScale':2.5,'viewportDip':[320,240],'hostAlignment':'center',
          'hostBackground':'explicit opaque white','host':a.host,'qualified':False,'originalPid':observation['pid'],
          'originalTerminalProof':True,'permissionRequests':False}
(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
print(json.dumps(manifest))
