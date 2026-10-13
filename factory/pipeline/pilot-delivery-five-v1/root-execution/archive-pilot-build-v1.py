from pathlib import Path
import argparse,hashlib,json,subprocess
p=argparse.ArgumentParser();p.add_argument('--host',choices=('image','rounded-stroke','custom-layout'),required=True);p.add_argument('--attempt',type=int,default=1);a=p.parse_args()
assert 1<=a.attempt<=10
base=Path('factory/pipeline/pilot-delivery-five-v1/root-execution')/(a.host+'-compile-r1')
out=base/('actual-prebuild-r'+str(a.attempt));out.mkdir()
remote='D:/Claude/swiftright/.factory-work/hosts/'+a.host+'/prebuild-r'+str(a.attempt)
for name in ('observation.json','compile.stdout.bin','compile.stderr.bin'):
 subprocess.run(['scp','-q','win:'+remote+'/'+name,str(out/name)],timeout=15,check=True)
def sha(path):
 assert path.is_file() and not path.is_symlink() and path.stat().st_size<=16777216
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
r=json.loads((out/'observation.json').read_text(encoding='utf-8-sig'))
plan=base/('plan-prebuild-native-r2.json' if a.attempt==2 else 'plan-prebuild-v4.json')
assert r['planSha256']==sha(plan)
assert r['ownedExited'] and r['streamsSealed'] and r['originalHandleRetained'] and r['kernelWait']==0 and r['jobActiveCount']==r['cleanupJobActive']==0
for stream in ('stdout','stderr'):
 path=out/('compile.'+stream+'.bin');assert path.stat().st_size==r[stream+'Bytes'] and sha(path)==r[stream+'Sha256']
if r['exitCode']==0:
 subprocess.run(['scp','-q','win:'+r['exePath'].replace('\\','/'),str(out/'FactoryProbe.exe')],timeout=20,check=True)
 assert sha(out/'FactoryProbe.exe')==r['exeSha256']
print(json.dumps({'host':a.host,'exitCode':r['exitCode'],'error':r['error'],'streamsSealed':True,'ownedExited':True,'qualification':'compile-only'}))
