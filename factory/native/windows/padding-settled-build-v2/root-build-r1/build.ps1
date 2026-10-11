$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
if((Get-FileHash -LiteralPath (Join-Path $root 'build-hosts-v2.ps1')).Hash.ToLowerInvariant() -cne '36437632f3c6ac8fb3a4b27058c0df67c61dbe08a5e0aac8508f814a99a8eff3'){throw 'Reviewed builder drift'}
$active=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$_.ProcessName -match '^(swift|swiftc|swift-build|swift-frontend)$'})
if($active.Count){throw 'Swift compiler already active; no concurrent root build'}
& "$root\build-hosts-v2.ps1" -Package "$root\package"
