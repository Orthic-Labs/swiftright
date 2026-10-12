"""Root-only bounded staging; no native run, lock acquisition, or deletion."""
from pathlib import Path
import argparse, json, subprocess

ap=argparse.ArgumentParser()
ap.add_argument('--revision',type=int,choices=range(1,21),required=True)
ap.add_argument('--count',type=int,choices=(1,20),default=1)
ap.add_argument('--host',choices=('rectangle','rounded-stroke','image','custom-layout'),default='rectangle')
a=ap.parse_args()
repo=Path('/Volumes/D/claude/swiftright')
tag=('r' if a.count==1 else 'count20-r')+str(a.revision)
generic=a.host!='rectangle'
if generic and a.count!=1:raise SystemExit('generic staging currently requires Count1')
stem=f'{a.host}-native-capture-r{a.revision}' if generic else f'rectangle-centered-capture-{tag}'
packet=repo/f'factory/pipeline/pilot-delivery-five-v1/root-execution/{stem}'
prep=json.loads((packet/'preparation.json').read_text())
zip_path=repo/f'.factory-work/pilot-delivery-five-v1/generic-native-capture/{a.host}-native-capture-r{a.revision}.zip' if generic else Path(prep['zip'])
assert zip_path.is_file() and not zip_path.is_symlink() and zip_path.stat().st_size<=16777216
remote_zip='D:/Claude/swiftright/.factory-work/'+zip_path.name
subprocess.run(['scp','-q','-o','BatchMode=yes','-o','ConnectTimeout=8',str(zip_path),'win:'+remote_zip],check=True,timeout=25)
source=packet/(f'install-native-capture-r{a.revision}.ps1' if generic else f'install-centered-count{a.count}-r{a.revision}.ps1')
script=packet/f'root-stage-count{a.count}-r{a.revision}.ps1'
assert source.stat().st_size<=2097152
checks="""$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\\Claude\\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy for rolling capture stage'}
"""
old_zip='D:\\Claude\\swiftright\\.factory-work\\'+zip_path.relative_to(repo/'.factory-work').as_posix().replace('/','\\')
script.open('x').write(checks+source.read_text().replace(old_zip,remote_zip.replace('/','\\')))
base=r'D:\Claude\swiftright\.factory-work\root-tools'
remote_tag=f'{a.host}-{tag}' if generic else tag
subprocess.run(['python3','/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root/run_pinned_windows_v1.py',
 '--script',str(script),'--remote-script',base+f'\\centered-stage-{remote_tag}.ps1',
 '--remote-receipt',base+f'\\centered-stage-{remote_tag}-transport.json',
 '--archive',str(packet/'stage-actual-r1-transport'),'--deadline','60'],check=True,timeout=105)
