$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\root-tools\transport-v1\controls-r1'
& (Join-Path $root 'test-root-transport-controls-v1.ps1') -RootPath $root -OutputPath (Join-Path $root 'source-controls.json')
if($LASTEXITCODE -ne 0){throw 'source controls failed'}
& (Join-Path $root 'run-root-transport-runtime-controls-v1.ps1') -RootPath $root -HelperSha256 '2ba026cc5939906e5320e6670a84a03097ef3f75c4aebefb37cb45a7c2417322' -WrapperSha256 '8b90eddb3352a54a2524ca4df020cea055f81d5fad7888f6ded45ea1a8db28cb' -OutputPath (Join-Path $root 'runtime-controls.json')
if($LASTEXITCODE -ne 0){throw 'runtime controls failed'}
exit 0
