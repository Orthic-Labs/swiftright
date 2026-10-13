# Count1 adapter transport commands (source-only)

Manifest: `dependencies/consumer-transport-manifest.json`. It pins 12 Mac context refs plus 2 canonical inputs. Windows does not install or execute Python.

## Mac to Dell input staging

Before Count1 producer issuance, stage every `requiredArchiveRefs` file under repo-relative paths on Dell. Include `adapter inputs` produced by Windows issuer only after current candidate metadata, tuple, case, runtime, renderer, executable, manifest, coordinator, and Count1 run refs are complete. Verify each staged file against manifest `sha256` and `bytes`; reject missing or drifted refs.

## Dell result bundle

Run in PowerShell on Dell after producer has written Count1 adapter inputs. `$RepoRoot` is `D:\Claude\swiftright`; `$AdapterInputsPath` is an explicit path to producer-issued inputs; `$TransportManifest` is parsed from pinned manifest.

```powershell
$ErrorActionPreference = 'Stop'
$repoRoot = 'D:\Claude\swiftright'
$manifestPath = Join-Path $repoRoot 'factory\native\windows\remaining-five-hosts-v6\root-admission-r3\dependencies\consumer-transport-manifest.json'
$TransportManifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$AdapterInputsPath = Read-Host 'Absolute path to producer-issued Count1 adapter inputs JSON'
$transport = Join-Path $repoRoot 'factory\native\windows\settled-capture-adapter-v3\transport\adapter-count1'
if (Test-Path -LiteralPath $transport) { throw 'Fresh adapter transport required' }
New-Item -ItemType Directory -Force -Path (Join-Path $transport 'archive') | Out-Null
Copy-Item -LiteralPath $AdapterInputsPath -Destination (Join-Path $transport 'inputs.json')
foreach ($ref in $TransportManifest.requiredArchiveRefs) {
  $src = Join-Path $repoRoot ($ref.path -replace '/', '\')
  if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "Missing transport ref: $($ref.path)" }
  $expected = ($ref.sha256 -replace '^sha256:', '').ToLowerInvariant()
  $actual = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actual -cne $expected) { throw "Transport hash drift: $($ref.path)" }
  $dst = Join-Path (Join-Path $transport 'archive') ($ref.path -replace '/', '\')
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  Copy-Item -LiteralPath $src -Destination $dst
}
$zip = Join-Path $transport 'adapter-count1-transport.zip'
Compress-Archive -LiteralPath (Join-Path $transport 'inputs.json'), (Join-Path $transport 'archive') -DestinationPath $zip -CompressionLevel Optimal -Force
(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
```

Transfer `adapter-count1-transport.zip` plus printed SHA256 from Dell to Mac. Do not rename contents.

## Mac consumer

On Mac, extract into a fresh directory, then run exact adapter & controls. Existing Mac `.venv` is consumer runtime.

```zsh
set -euo pipefail
repo=/Volumes/D/claude/swiftright
transport="$repo/factory/native/windows/settled-capture-adapter-v3/transport/adapter-count1"
rm -rf "$transport"
mkdir -p "$transport"
unzip -q /path/from/Dell/adapter-count1-transport.zip -d "$transport"
cd "$repo"
factory/.venv/bin/python factory/native/windows/settled-capture-adapter-v3/run-adapter.py \
  --inputs "$transport/inputs.json" \
  --archive-root "$transport/archive" \
  --output "$transport/normalized.json"
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/test-candidate-fault-controls.py
```

Consumer output remains observational (`qualified=false`); root must independently inspect Windows receipts & lifecycle facts before any qualification decision.
