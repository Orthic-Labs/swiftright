$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\custom-layout-colors';$saved=Join-Path $stage 'primary-final-before-direct-r1'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop busy'}
if(Test-Path -LiteralPath $saved){throw 'immutable archive exists'}
if((Get-FileHash -LiteralPath (Join-Path $stage 'final-r1\observation.json')).Hash.ToLowerInvariant() -cne '6c0891e7786b672a32645daf2d93f8684007215ba1f76cf0286a2e289780d1e0'){throw 'archived primary final receipt drift'}
New-Item -ItemType Directory -Path $saved|Out-Null
foreach($name in @('final-r1','requests-final-r1','prebuild-archive-attempt-1','package\plan-final-v4.json','build-owned-final-v1.ps1')){
 $p=Join-Path $stage $name
 if(Test-Path -LiteralPath $p){Move-Item -LiteralPath $p -Destination (Join-Path $saved (Split-Path $name -Leaf))}
}
@{status='preserved';saved=$saved;deleted=$false;nativeActions=0}|ConvertTo-Json
