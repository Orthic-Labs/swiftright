"""Compile fresh Mac reference on internal disk; never request permissions."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
p=argparse.ArgumentParser();p.add_argument('--host',choices=('image','rounded-stroke','custom-layout','bundled-font'),required=True);a=p.parse_args()
repo=Path('/Volumes/D/claude/swiftright')
name={'image':'text-shape-image/image-host-package-v1','rounded-stroke':'text-shape-image/rounded-stroke-host-v1','custom-layout':'stack-layout/custom-layout-host-v1','bundled-font':'text-shape-image/bundled-font-readiness-v1'}[a.host]
packet=repo/'factory/pipeline/pilot-delivery-five-v1'/name/'mac-source'
scratch=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1')/(a.host+'-delivery-mac-r1')
scratch.mkdir();source=scratch/'source';source.mkdir()
out=repo/'factory/pipeline/pilot-delivery-five-v1/root-execution'/(a.host+'-mac-build-r1');out.mkdir()
rows=[];total=0
for path in packet.rglob('*'):
 if path.is_dir():continue
 assert path.is_file() and not path.is_symlink() and path.stat().st_size<=1048576
 total+=path.stat().st_size;assert total<=4194304 and len(rows)<128
 b=path.read_bytes();rel=path.relative_to(packet);dest=source/rel;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(b)
 rows.append({'path':rel.as_posix(),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
app=scratch/'FactoryProbe.app';(app/'Contents/MacOS').mkdir(parents=True);(app/'Contents/Resources').mkdir()
(app/'Contents/Info.plist').write_text('<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleExecutable</key><string>FactoryProbe</string><key>CFBundleIdentifier</key><string>com.swiftright.factory.'+a.host+'</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>')
def run(label,argv,limit):
 start=time.time()
 with (out/(label+'.stdout.bin')).open('xb') as stdout,(out/(label+'.stderr.bin')).open('xb') as stderr:
  r=subprocess.run(argv,cwd=source,stdout=stdout,stderr=stderr,timeout=limit)
 receipt={'kind':'factory-mac-pilot-compile-step-v1','argv':argv,'cwd':str(source),'exitCode':r.returncode,'elapsedSeconds':time.time()-start,'nativeActions':0,'permissionRequests':False}
 (out/(label+'.json')).write_text(json.dumps(receipt,indent=2)+'\n')
 assert r.returncode==0,label+' failed'
if a.host=='image':
 run('assets',['/usr/bin/xcrun','actool','--compile',str(app/'Contents/Resources'),'--platform','macosx','--minimum-deployment-target','14.0',str(source/'Resources/FactoryRGBA.xcassets')],90)
 assert (app/'Contents/Resources/Assets.car').is_file()
exe=app/'Contents/MacOS/FactoryProbe'
module='CustomLayoutMacHost' if a.host=='custom-layout' else 'FactoryProbe'
run('compile',['/usr/bin/xcrun','swiftc','-parse-as-library','-O','-j1','-num-threads','1','-module-cache-path',str(scratch/'module-cache'),'-o',str(exe),str(source/'Sources'/module/'Witness.swift'),str(source/'Sources'/module/'CaptureHost.swift')],240)
assert exe.is_file() and exe.stat().st_size<=16777216
h=hashlib.sha256()
with exe.open('rb') as f:
 for b in iter(lambda:f.read(1048576),b''):h.update(b)
receipt={'kind':'factory-mac-pilot-build-v1','host':a.host,'binaryPath':str(exe),'binaryHash':h.hexdigest(),'sourceBindings':rows,'bytes':total,'nativeActions':0,'permissionRequests':False,'qualification':'compiled-not-captured','memoryCapBytes':1073741824,'internalScratch':str(scratch)}
(out/'build-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'host':a.host,'status':'compiled-not-captured','binaryHash':h.hexdigest()}))
