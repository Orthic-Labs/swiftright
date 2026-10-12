"""Fetch & verify immutable centered native archive; bounded streaming only."""
from pathlib import Path, PureWindowsPath
import argparse, hashlib, json, subprocess, zipfile

p=argparse.ArgumentParser()
p.add_argument('--revision',type=int,choices=range(1,21),required=True)
p.add_argument('--count',type=int,choices=(1,20),default=1)
p.add_argument('--attempt',type=int,choices=range(1,5),default=1)
p.add_argument('--host',choices=('rectangle','rounded-stroke','image','stack-overlay','custom-layout','bundled-font'),default='rectangle')
a=p.parse_args()
tag=('r' if a.count==1 else 'count20-r')+str(a.revision)
repo=Path('/Volumes/D/claude/swiftright')
generic=a.host!='rectangle'
if generic and a.count!=1:raise SystemExit('generic archive currently requires Count1')
stem=f'{a.host}-native-capture-r{a.revision}' if generic else 'rectangle-centered-capture-'+tag
base=repo/'factory/pipeline/pilot-delivery-five-v1/root-execution'/stem
out=base/f'actual-native-r{a.attempt}'
out.mkdir()
if generic:
    preparation=base/'preparation.json'
    assert preparation.is_file() and not preparation.is_symlink() and preparation.stat().st_size<=4194304
    prep=json.loads(preparation.read_text())
    stage=PureWindowsPath(prep['compileReceiptPath']).parent.parent
    assert stage.parent==PureWindowsPath(r'D:\Claude\swiftright\.factory-work\hosts')
    assert stage.name in (a.host,a.host+'-centered',a.host+'-circular',a.host+'-observation',a.host+'-colors',a.host+'-boundary',a.host+'-star-observation')
    remote=(stage/'captures'/f'count1-r{a.revision}').as_posix()
else:
    remote='D:/Claude/swiftright/.factory-work/hosts/rectangle/captures/centered-'+tag
zipname=f'actual-native-centered-count{a.count}.zip'
manifestname=f'actual-native-centered-count{a.count}-manifest.json'
for name in (manifestname,zipname):
    subprocess.run(['scp','-q','-o','BatchMode=yes','-o','ConnectTimeout=8','win:'+remote+'/'+name,str(out/name)],check=True,timeout=25)
def sha(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=33554432
    h=hashlib.sha256()
    with path.open('rb') as stream:
        for data in iter(lambda:stream.read(1048576),b''):h.update(data)
    return h.hexdigest()
assert (out/manifestname).stat().st_size<=2097152
m=json.loads((out/manifestname).read_text(encoding='utf-8-sig'))
assert m['kind']=='factory-rectangle-centered-actual-native-archive-v1'
assert m['count']==a.count and m['lockReleased'] is True and m['qualified'] is False
assert len(m['files'])<=1600 and m['bytes']<=33554432
assert (out/zipname).stat().st_size==m['zipBytes'] and sha(out/zipname)==m['zipSha256']
expected={row['path']:row for row in m['files']}
assert len(expected)==len(m['files'])
total=0
with zipfile.ZipFile(out/zipname) as archive:
    assert len(archive.infolist())==len(expected)
    for info in archive.infolist():
        relative=Path(info.filename)
        assert not relative.is_absolute() and '..' not in relative.parts
        assert '\\' not in info.filename and ':' not in info.filename
        row=expected[info.filename]
        assert info.file_size==row['bytes'] and info.file_size<=16777216
        total+=info.file_size
        assert total<=33554432
        dest=out/'files'/relative
        dest.parent.mkdir(parents=True,exist_ok=True)
        with archive.open(info) as source,dest.open('xb') as target:
            while True:
                data=source.read(1048576)
                if not data:break
                target.write(data)
        assert sha(dest)==row['sha256']
assert total==m['bytes']
print(json.dumps({'count':a.count,'files':len(expected),'bytes':total,'status':'actual-bytes-verified','qualified':False}))
