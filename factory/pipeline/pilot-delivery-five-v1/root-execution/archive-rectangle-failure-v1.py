from pathlib import Path
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--revision',type=int,choices=(2,4,5),default=2);a=p.parse_args()
base=Path('factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-capture-r'+str(a.revision))
source=base/'failure-inventory-r1-transport/transport.json.stdout.bin'
assert source.stat().st_size<1048576
m=json.loads(source.read_text(encoding='utf-8-sig'))
assert len(m['files'])<=128 and m['bytes']<=33554432
out=base/'failure-actual';out.mkdir()
for row in m['files']:
 rel=Path(row['path']);assert not rel.is_absolute() and '..' not in rel.parts
 dest=out/rel;dest.parent.mkdir(parents=True,exist_ok=True)
 remote=m['root'].replace('\\','/')+'/'+row['path']
 subprocess.run(['scp','-q','win:'+remote,str(dest)],check=True,timeout=15)
 assert dest.is_file() and not dest.is_symlink() and dest.stat().st_size==row['bytes']
 h=hashlib.sha256()
 with dest.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 assert h.hexdigest()==row['sha256']
(out/'archive-manifest.json').write_text(json.dumps(m,indent=2)+'\n')
print(json.dumps({'files':len(m['files']),'bytes':m['bytes'],'status':'archived-failure-not-qualified'}))
