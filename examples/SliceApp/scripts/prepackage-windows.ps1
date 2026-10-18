# prePackage for the Windows MSIX target (run on the Windows host): build, verify, stage the pinned renderer,
# then stage the flat payload that right-release msix consumes. Signing happens in right-release, never here.
#
# F1 (renderer packaging): swiftright_render.dll is loaded dynamically (Bridge.load), so no import-table walk finds
# it. This script fails closed unless the renderer matches Windows\renderer-pin.json byte for byte, copies it to
# .build\renderer (swift-package.json windows.include picks it up and walks its import closure), and after staging
# re-verifies the staged copy and the stage manifest.
#   -Config          swift-package config (default swift-package.json; CI passes the generated swift-package.ci.json)
#   -RendererSource  path to swiftright_render.dll (default: $env:SWIFTRIGHT_RENDERER_SRC, else the pin's defaultSource)
param([string]$RendererSource = '', [string]$Config = 'swift-package.json')
$ErrorActionPreference = 'Stop'
$app = Resolve-Path (Join-Path $PSScriptRoot '..')
$pin = Get-Content (Join-Path $app 'Windows\renderer-pin.json') -Raw | ConvertFrom-Json
if (-not $RendererSource) { $RendererSource = [Environment]::GetEnvironmentVariable($pin.sourceEnv) }
if (-not $RendererSource) { $RendererSource = $pin.defaultSource }
# A repository-relative source (the tracked tuple 12 renderer) resolves against the repository root, two levels above the app.
if (-not [System.IO.Path]::IsPathRooted($RendererSource)) { $RendererSource = Join-Path (Resolve-Path (Join-Path $app '..\..')) $RendererSource }

function Assert-Pinned([string]$file, [string]$what) {
    if (-not (Test-Path -LiteralPath $file)) { throw "$what missing: $file" }
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if ($actual -ne $pin.sha256.ToUpperInvariant()) { throw "$what sha256 mismatch: $file is $actual, pin (ABI $($pin.abi)) is $($pin.sha256)" }
    "renderer pinned ok: $what sha256=$actual"
}

# Fail before any build work if the renderer is absent or not the pinned bytes.
Assert-Pinned $RendererSource 'renderer source'

& (Join-Path $PSScriptRoot 'build-windows.ps1')
Set-Location $app

$rendererDir = Join-Path $app '.build\renderer'
Remove-Item -Recurse -Force $rendererDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $rendererDir | Out-Null
$rendererCopy = Join-Path $rendererDir $pin.file
Copy-Item -LiteralPath $RendererSource $rendererCopy -Force
Assert-Pinned $rendererCopy 'renderer copy'

# RIGHT_RELEASE_CLI (CI) names the right-release entry point installed at the repository root; unset, pnpm exec resolves it here.
if ($env:RIGHT_RELEASE_CLI) { & node $env:RIGHT_RELEASE_CLI swift-package windows-stage --config $Config }
else { & pnpm exec right-release swift-package windows-stage --config $Config }
if ($LASTEXITCODE -ne 0) { throw "windows-stage failed (exit $LASTEXITCODE)" }

# Post-stage proof: the renderer is in the stage directory beside the exe, byte-identical to the pin, and the
# stage manifest lists it plus the declared shipped closure entries.
& (Join-Path $PSScriptRoot 'verify-package-layout.ps1') -Mode Stage -Root (Join-Path $app '.build\msix-stage')
if ($LASTEXITCODE -ne 0) { throw "verify-package-layout (Stage) failed (exit $LASTEXITCODE)" }
