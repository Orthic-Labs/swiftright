$ErrorActionPreference = 'Stop'
$root = 'D:\Claude\swiftright\.work\sr0-stage-tools'
$manifest = Join-Path $root 'manifest.json'
if ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant() -ne '60df4d339bfaf5fbcb9ab588a693118b34ebe90b71a0ab660c83a1a3c708d4fe') { throw 'source transfer manifest mismatch' }
$m = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json
foreach ($f in $m.files) {
  $path = Join-Path $root ($f.path -replace '/', '\')
  if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $f.sha256 -or (Get-Item -LiteralPath $path).Length -ne $f.bytes) { throw "source transfer mismatch: $path" }
}
Write-Output "SOURCE_TRANSFER_OK count=$($m.files.Count)"
$preflight = Join-Path $root 'probes\sr0-s\fresh-on-bridge\scripts\preflight-ps1.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $preflight -Root $root
if ($LASTEXITCODE -ne 0) { throw "source parse failed exit=$LASTEXITCODE" }
$audit = Join-Path $root 'probes\sr0-s\fresh-on-bridge\scripts\audit-tuple.ps1'
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $audit
$rc = $LASTEXITCODE
if ($rc -notin @(0,2)) { throw "audit failed exit=$rc" }
Write-Output "AUDIT_EXIT $rc"
