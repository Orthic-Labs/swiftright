"""Pin one source-only pilot packet to bounded native retained-handle compiler lifecycle."""
from pathlib import Path
import argparse,hashlib,json,zipfile
p=argparse.ArgumentParser();p.add_argument('--host',choices=('image','image-v2','image-star-provider','rounded-stroke','rounded-stroke-centered','rounded-stroke-circular','stack-overlay-centered','custom-layout','custom-layout-v2'),required=True);a=p.parse_args()
repo=Path('/Volumes/D/claude/swiftright')
rel={'image':'text-shape-image/image-host-package-v1','image-v2':'text-shape-image/image-host-package-v2','image-star-provider':'text-shape-image/image-system-star-fill-v1/windows-source/provider-bound-delivery-v2','rounded-stroke':'text-shape-image/rounded-stroke-host-v1','rounded-stroke-centered':'text-shape-image/rounded-stroke-host-v1/centered-delivery-v1','rounded-stroke-circular':'text-shape-image/rounded-stroke-host-v1/circular-centered-delivery-v2','stack-overlay-centered':'stack-layout/stack-overlay-centered-delivery-v1','custom-layout':'stack-layout/custom-layout-host-v1','custom-layout-v2':'stack-layout/custom-layout-host-v2'}[a.host]
new_host=a.host!='image'
packet=repo/'factory/pipeline/pilot-delivery-five-v1'/rel/'package'
out=repo/'factory/pipeline/pilot-delivery-five-v1/root-execution'/(a.host+'-compile-r1');out.mkdir()
def rd(path,cap=4194304):
 assert path.is_file() and not path.is_symlink() and path.stat().st_size<=cap
 return path.read_bytes()
def sha(b):return hashlib.sha256(b).hexdigest()
def jd(v):return (json.dumps(v,indent=2,sort_keys=True)+'\n').encode()
raw=rd(packet/'plan.json');plan=json.loads(raw)
case_raw=rd(packet/'case.json');canonical_case=json.loads(case_raw)['id']
assert plan['runtimeSourceTreeHash']=='sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
plan['rendererSha256']=plan['rendererSha256'].removeprefix('sha256:')
plan['compilerHash']=plan['compilerHash'].removeprefix('sha256:')
assert plan['rendererSha256']=='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
assert plan['compilerHash']=='1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
assert plan.get('sourceCommit',plan.get('runtimeSourceCommit'))=='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
files={}
for path in packet.rglob('*'):
 if path.is_dir():continue
 assert not path.is_symlink()
 relpath=path.relative_to(packet).as_posix();files['package/'+relpath]=rd(path)
assert len(files)<=128 and sum(map(len,files.values()))<=16777216
for row in plan['sourceBindings']:
 data=files['package/'+row['path']]
 assert len(data)==row['bytes'] and sha(data)==row['sha256'].replace('sha256:','')
actual={k[8:] for k in files if k=='package/Package.swift' or k.startswith('package/Sources/')}
expected={r['path'] for r in plan['sourceBindings'] if r['path']=='Package.swift' or r['path'].startswith('Sources/')}
assert actual==expected
assert sha(files['package/runtime-source-tree.json'])==plan['runtimeSourceTreeHash'][7:]
receiptHash=sha(files['package/runtime-source-receipt.json'])
assert receiptHash==plan['runtimeSourceReceiptHash'][7:]
helper_source=repo/'factory/pipeline/pilot-delivery-five-v1/root-execution/Sr0OwnedJobProcess.cs'
helper=out/'Sr0OwnedJobProcess.cs'
hb=rd(helper_source)
helper.write_bytes(hb)
assert sha(hb)=='112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e'
base=repo/'factory/native/windows/pilot-rectangle-fixed-root-v2/build-owned-v4.ps1'
adapter=rd(base);assert sha(adapter)=='f88932bcaaeb536f3dd7103b8401221cf1a27384fec75e928ebfd397dac53c7d'
text=adapter.decode()
text=text.replace("$stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle'","$stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\"+a.host+"'")
text=text.replace('factory-rectangle-compiler-plan-v2','factory-pilot-five-compiler-plan-v1').replace('swiftui.shapes.rectangle-fill.pilot-next',plan['candidate'])
text=text.replace('factory-rectangle-','factory-pilot-five-')
assert text.count('--jobs 1 -c release')==1
if new_host:
 text=text.replace('build --package-path','build --build-system native -v --package-path')
 text=text.replace('--jobs 1 -c release','--jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release')
 text=text.replace('out\\Products\\Release-windows-x86_64\\FactoryProbe.exe','x86_64-unknown-windows-msvc\\release\\FactoryProbe.exe')
 text=text.replace('swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.*',canonical_case)
 if a.host=='image-v2': text=text.replace("$scratch=Join-Path $package 'build-bound-r1\\scratch'", "$scratch=Join-Path $package 'build-bounded-r2\\scratch'")
else:
 text=text.replace('--jobs 1 -c release','--jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release')
check=" if((Hash (Join-Path $package 'runtime-source-receipt.json')) -cne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'runtime receipt drift'}\n"
text=text.replace(' Verify-Rows $package $plan.sourceBindings $true\n',' Verify-Rows $package $plan.sourceBindings $true\n'+check)
files['build-owned-pilot-v1.ps1']=text.encode();files['Sr0OwnedJobProcess.cs']=hb
stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\'+a.host
package=stage+'\\package';scratch=package+('\\build-bounded-r2\\scratch' if a.host=='image-v2' else '\\build-bound-r1\\scratch')
plan.update(kind='factory-pilot-five-compiler-plan-v1',phase='prebuild',runtimeSourceCommit='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b',helperSha256=sha(hb),case=None,expectedHostHash=None)
plan['packageSourcePath']='factory/pipeline/pilot-delivery-five-v1/'+rel+'/package'
plan['compileRequest'].update(packagePath=package,scratchPath=scratch,maxParallelJobs=1,maxFrontendThreads=1,memoryCapBytes=1073741824)
if new_host:
 dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
 plan['packageStagePath']=package
 plan['scratchPath']=scratch
 plan['compileRequest']['buildSystem']='native'
 plan['compileRequest']['argv']=['build','--build-system','native','-v','--package-path',package,'--scratch-path',scratch,'--jobs','1','-Xswiftc','-j1','-Xswiftc','-num-threads','-Xswiftc','1','-c','release','-Xlinker','/MANIFEST:EMBED','-Xlinker',dep,'-Xlinker','/SUBSYSTEM:WINDOWS','-Xlinker','/ENTRY:mainCRTStartup']
plan['tuple']={'id':'sr1-'+a.host+'-delivery-r11-20261012-r1','rendererHash':'sha256:'+plan['rendererSha256'],'hostHashes':{'windows':None},'runtimeSourceCommit':plan['runtimeSourceCommit'],'abiVersion':'0.6'}
plan['packetPlanHash']='sha256:'+sha(raw);plan['executionEligible']=False;plan['nativeParity']='hold'
files['package/packet-plan.json']=raw
files['package/plan-prebuild-v4.json']=jd(plan)
(out/'plan-prebuild-v4.json').write_bytes(files['package/plan-prebuild-v4.json'])
(out/'build-owned-pilot-v1.ps1').write_bytes(files['build-owned-pilot-v1.ps1'])
manifest={'kind':'factory-pilot-five-root-compile-stage-v1','files':[{'path':k,'bytes':len(b),'sha256':sha(b)} for k,b in files.items()],'nativeActions':0}
files['stage-manifest.json']=jd(manifest)
cache=repo/'.factory-work/pilot-delivery-five-v1';cache.mkdir(parents=True,exist_ok=True);z=cache/(a.host+'-delivery-compile-r1.zip')
with zipfile.ZipFile(z,'x',zipfile.ZIP_DEFLATED) as archive:
 for k,b in files.items():archive.writestr(k,b)
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='__STAGE__'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'native session busy'}
if(Test-Path -LiteralPath $Stage){throw 'fresh pilot host stage required'}
$Zip='D:\Claude\swiftright\.factory-work\__ZIP__'
if((Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant() -cne '__ZIPHASH__'){throw 'pilot zip drift'}
Expand-Archive -LiteralPath $Zip -DestinationPath $Stage
$M=Get-Content -LiteralPath (Join-Path $Stage 'stage-manifest.json') -Raw|ConvertFrom-Json
$Total=0;foreach($R in @($M.files)){$F=Get-Item -LiteralPath (Join-Path $Stage $R.path) -Force;$Total+=$F.Length;if($F.Length -ne $R.bytes -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant() -cne $R.sha256){throw 'pilot staged source drift'}}
if(@($M.files).Count -gt 128 -or $Total -gt 16777216){throw 'pilot stage cap'}
$Plan=Join-Path $Stage 'package\plan-prebuild-v4.json';$Builder=Join-Path $Stage 'build-owned-pilot-v1.ps1'
& $Builder -PlanPath $Plan -PlanSha256 '__PLANHASH__' -Phase prebuild -Attempt 1 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 '__PLANHASH__' -Phase prebuild -Attempt 1
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r1\observation.json') -Raw
'''
for k,v in {'STAGE':stage,'ZIP':z.name,'ZIPHASH':sha(rd(z)),'PLANHASH':sha(files['package/plan-prebuild-v4.json'])}.items():script=script.replace('__'+k+'__',v)
(out/'stage-build-r1.ps1').write_text(script)
(out/'preparation.json').write_bytes(jd({'host':a.host,'packageFiles':len(manifest['files']),'packetPlanHash':sha(raw),'planSha256':sha(files['package/plan-prebuild-v4.json']),'builderHash':sha(files['build-owned-pilot-v1.ps1']),'helperHash':sha(hb),'memoryCapBytes':1073741824,'nativeActions':0,'qualification':'pending-actual-compile'}))
print(json.dumps({'host':a.host,'installer':str(out/'stage-build-r1.ps1'),'zip':str(z),'nativeActions':0,'rootCopyRequired':True}))
