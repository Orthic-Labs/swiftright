$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r4'
$global:LASTEXITCODE=0
& (Join-Path $root 'test-root-transport-controls-v1.ps1') -RootPath $root -OutputPath (Join-Path $root 'source-controls.json')
if($LASTEXITCODE -ne 0){throw 'source controls failed'}
$global:LASTEXITCODE=0
& (Join-Path $root 'run-root-transport-runtime-controls-v1.ps1') -RootPath $root -HelperSha256 'f70ab1ebe1f70ea4833bb1944a1195e89875684882ae0541a5f9a3da5904dd2c' -WrapperSha256 '1d70d8f6de962daaac2d9c7e71930a467fc9bb2aac332e8945e5b3c31fd6f1ee' -OutputPath (Join-Path $root 'runtime-controls.json')
if($LASTEXITCODE -ne 0){throw 'runtime controls failed'}
exit 0
