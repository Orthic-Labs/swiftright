$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright'
$root=Join-Path $repo '.factory-work\hosts\padding-window-diagnosis'
$source=Join-Path $repo 'factory\native\windows\padding-capture-lease-build-v1'
$stage=Get-Content -LiteralPath (Join-Path $source 'root-stage-manifest.json') -Raw|ConvertFrom-Json
foreach($r in $stage.files){$p=Join-Path $repo $r.path;$h=(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower();if(('sha256:'+$h) -cne [string]$r.hash){throw ('Source pin drift: '+$r.path)};if((Get-Item -LiteralPath $p).Length -ne $r.bytes){throw 'Source size drift'};if(([string]$r.path).StartsWith('factory/native/windows/padding-capture-lease-build-v1/')){$rel=([string]$r.path).Substring('factory/native/windows/padding-capture-lease-build-v1/'.Length);if((Get-FileHash -LiteralPath (Join-Path $root $rel) -Algorithm SHA256).Hash.ToLower() -cne $h){throw 'Rolling source drift'}}}
Push-Location $root
try{
 & (Join-Path $root 'run-controls.ps1')
 & (Join-Path $root 'run-stream-controls.ps1')
 & (Join-Path $root 'build-hosts-v2.ps1') -Package (Join-Path $root 'package') -PreflightOnly
 & (Join-Path $root 'build-hosts-v2.ps1') -Package (Join-Path $root 'package')
} finally {Pop-Location}
