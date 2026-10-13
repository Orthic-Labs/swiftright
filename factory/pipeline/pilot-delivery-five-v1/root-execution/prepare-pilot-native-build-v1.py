from pathlib import Path
import argparse,base64,hashlib,json
p=argparse.ArgumentParser();p.add_argument('--host',choices=('image','rounded-stroke','custom-layout'),required=True);a=p.parse_args()
out=Path('factory/pipeline/pilot-delivery-five-v1/root-execution')/(a.host+'-compile-r1')
def rd(path):
 assert path.is_file() and not path.is_symlink() and path.stat().st_size<1048576
 return path.read_bytes()
def sha(b):return hashlib.sha256(b).hexdigest()
oldplan=rd(out/'plan-prebuild-v4.json');oldbuilder=rd(out/'build-owned-pilot-v1.ps1')
plan=json.loads(oldplan);package=plan['compileRequest']['packagePath'];scratch=plan['compileRequest']['scratchPath']
dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
plan['compileRequest']['argv']=['build','--build-system','native','-v','--package-path',package,'--scratch-path',scratch,'--jobs','1','-Xswiftc','-j1','-Xswiftc','-num-threads','-Xswiftc','1','-c','release','-Xlinker','/MANIFEST:EMBED','-Xlinker',dep,'-Xlinker','/SUBSYSTEM:WINDOWS','-Xlinker','/ENTRY:mainCRTStartup']
plan['compileRequest']['buildSystem']='native';plan['boundedFrontendEvidence']='pending emitted command review; requested flags alone do not prove consumption'
data=(json.dumps(plan,indent=2,sort_keys=True)+'\n').encode()
builder=oldbuilder.decode();assert builder.count("$argv='build --package-path")==1
builder=builder.replace("$argv='build --package-path","$argv='build --build-system native -v --package-path")
assert builder.count("out\\Products\\Release-windows-x86_64\\FactoryProbe.exe")==1
builder=builder.replace("out\\Products\\Release-windows-x86_64\\FactoryProbe.exe","x86_64-unknown-windows-msvc\\release\\FactoryProbe.exe").encode()
(out/'plan-prebuild-native-r2.json').write_bytes(data);(out/'build-owned-native-r2.ps1').write_bytes(builder)
stage='D:\\Claude\\swiftright\\.factory-work\\hosts\\'+a.host
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='__STAGE__';$Plan=Join-Path $Stage 'package\plan-prebuild-v4.json';$Builder=Join-Path $Stage 'build-owned-pilot-v1.ps1'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native stage busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'native session busy'}
if((Get-FileHash -LiteralPath $Plan).Hash.ToLowerInvariant() -cne '__OLDPLAN__' -or (Get-FileHash -LiteralPath $Builder).Hash.ToLowerInvariant() -cne '__OLDBUILDER__'){throw 'rolling compiler source drift'}
$Backup=Join-Path $Stage 'prebuild-r1\request-plan.json';if(Test-Path -LiteralPath $Backup){throw 'fresh old request archive required'};Copy-Item -LiteralPath $Plan -Destination $Backup
Copy-Item -LiteralPath $Builder -Destination (Join-Path $Stage 'prebuild-r1\request-builder.ps1')
[IO.File]::WriteAllBytes($Plan,[Convert]::FromBase64String('__PLAN__'));[IO.File]::WriteAllBytes($Builder,[Convert]::FromBase64String('__BUILDER__'))
if((Get-FileHash -LiteralPath $Plan).Hash.ToLowerInvariant() -cne '__PLANHASH__' -or (Get-FileHash -LiteralPath $Builder).Hash.ToLowerInvariant() -cne '__BUILDERHASH__'){throw 'written compiler request drift'}
& $Builder -PlanPath $Plan -PlanSha256 '__PLANHASH__' -Phase prebuild -Attempt 2 -PreflightOnly
& $Builder -PlanPath $Plan -PlanSha256 '__PLANHASH__' -Phase prebuild -Attempt 2
Get-Content -LiteralPath (Join-Path $Stage 'prebuild-r2\observation.json') -Raw
'''
for k,v in {'STAGE':stage,'OLDPLAN':sha(oldplan),'OLDBUILDER':sha(oldbuilder),'PLAN':base64.b64encode(data).decode(),'BUILDER':base64.b64encode(builder).decode(),'PLANHASH':sha(data),'BUILDERHASH':sha(builder)}.items():script=script.replace('__'+k+'__',v)
(out/'retry-native-build-r2.ps1').write_text(script)
print(json.dumps({'host':a.host,'planSha256':sha(data),'builderSha256':sha(builder),'nativeActions':0}))
