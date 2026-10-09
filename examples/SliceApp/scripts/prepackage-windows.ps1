# prePackage for the Windows MSIX target (run on the Windows host): build, verify, then stage the flat payload
# that right-release msix consumes. Signing happens in right-release, never here.
$ErrorActionPreference = 'Stop'
$app = Resolve-Path (Join-Path $PSScriptRoot '..')
& (Join-Path $PSScriptRoot 'build-windows.ps1')
Set-Location $app
& pnpm exec right-release swift-package windows-stage --config swift-package.json
if ($LASTEXITCODE -ne 0) { throw "windows-stage failed (exit $LASTEXITCODE)" }
