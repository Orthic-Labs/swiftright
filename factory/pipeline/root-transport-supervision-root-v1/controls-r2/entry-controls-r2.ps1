$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r2'
$global:LASTEXITCODE=0
& (Join-Path $root 'test-root-transport-controls-v1.ps1') -RootPath $root -OutputPath (Join-Path $root 'source-controls.json')
if($LASTEXITCODE -ne 0){throw 'source controls failed'}
$global:LASTEXITCODE=0
& (Join-Path $root 'run-root-transport-runtime-controls-v1.ps1') -RootPath $root -HelperSha256 'cf3d74ac5e11cb4382e236d67f302396a52fdb71773f20c92a6fd576fff2d718' -WrapperSha256 'f448d6437ac4cb43009eea10debd35fe0cb566e790f900ab21df6122cc6eab2c' -OutputPath (Join-Path $root 'runtime-controls.json')
if($LASTEXITCODE -ne 0){throw 'runtime controls failed'}
exit 0
