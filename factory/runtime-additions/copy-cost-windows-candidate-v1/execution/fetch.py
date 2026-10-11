from pathlib import Path
import importlib.util,json,hashlib
H=Path(__file__).resolve().parent;P=H.parent
sp=importlib.util.spec_from_file_location('dispatch',P/'dispatch.py');d=importlib.util.module_from_spec(sp);sp.loader.exec_module(d)
_,run=d.remote_roots();obs=run.replace('copycost-run-','copycost-observe-');dest=H/'results';dest.mkdir(exist_ok=True)
d.invoke('execution/scp-receipt',['scp','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+run.replace('\\','/')+'/receipt.json',str(dest)])
r=json.loads((dest/'receipt.json').read_text(encoding='utf-8-sig'))
for v in r['variants']:
 target=dest/v['name'];target.mkdir(exist_ok=True)
 d.invoke('execution/scp-process-'+v['name'],['scp','-r','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+run.replace('\\','/')+'/'+v['name']+'/process',str(target)])
 artifacts=target/'artifacts';artifacts.mkdir(exist_ok=True)
 for i,b in enumerate(v['executables']):
  local=artifacts/b['path'].replace('\\','/').split('/')[-1]
  d.invoke('execution/scp-binary-'+v['name']+'-'+str(i),['scp','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+b['path'].replace('\\','/'),str(local)])
  assert local.stat().st_size==b['bytes'] and hashlib.sha256(local.read_bytes()).hexdigest()==b['sha256']
d.invoke('execution/scp-observation',['scp','-r','-o','BatchMode=yes','-o','ConnectTimeout=10','win:'+obs.replace('\\','/'),str(dest)])
