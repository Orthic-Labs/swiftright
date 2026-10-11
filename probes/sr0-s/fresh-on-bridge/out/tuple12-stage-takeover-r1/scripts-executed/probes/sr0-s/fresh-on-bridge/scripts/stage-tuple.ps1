<#
Stage one SR0 tuple on the Dell from a single clone of bogusyogi/swiftright.
Build and copy only: no GUI, no scheduled task, no run of any built exe, no deletion.
Run as a -File script through win:
  powershell -NoProfile -ExecutionPolicy Bypass -File stage-tuple.ps1 -Commit <sha> -Root D:\Claude\swiftright\.work\sr0-r12 -RendererDll <path> -ExpectRenderer <sha256> -ScriptOverride D:\Claude\swiftright\.work\sr0-overrides
Derived from docs/sr0-tuple09-staging.md, sr0-tuple10-staging.md and sr0-tuple11-staging.md.
#>
param(
  [Parameter(Mandatory = $true)][string]$Commit,
  [Parameter(Mandatory = $true)][string]$Root,
  [Parameter(Mandatory = $true)][string]$RendererDll,
  [Parameter(Mandatory = $true)][string]$ExpectRenderer,
  [string]$ScriptOverride = '',
  [switch]$Resume
)

# Native stderr (git, swift) must not become terminating under Stop; exit codes are checked instead.
$ErrorActionPreference = 'Continue'
$script:Step = 'init'
$SwiftRuntime = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$Repo = 'https://github.com/bogusyogi/swiftright'
$RelDir = 'scratch\out\Products\Release-windows-x86_64'
$Src = Join-Path $Root 'src'
$Smoke = Join-Path $Root 'smoke'
$Work = Join-Path $Root 'workload'
$Geo = Join-Path $Root 'geomodal'
$Rend = Join-Path $Root 'renderer'
$Tools = Join-Path $Root 'stage-tools'
$Dll = Join-Path $Rend 'swiftright_render.dll'
$Pin = $ExpectRenderer.ToUpper()
$PinLower = $ExpectRenderer.ToLower()

function Step([string]$name) { $script:Step = $name; Write-Output "STEP $name" }
function Need([string]$p) { if (-not (Test-Path -LiteralPath $p)) { throw "missing: $p" } }
function Sha([string]$p) { Need $p; (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
function StageScript([string]$relative) {
  $p = if ($ScriptOverride) { Join-Path $ScriptOverride $relative } else { Join-Path $Src $relative }
  Need $p
  $p
}

function Put-Dll([string]$dir) {
  New-Item -ItemType Directory -Force -Path $dir -ErrorAction Stop | Out-Null
  $d = Join-Path $dir 'swiftright_render.dll'
  Copy-Item -LiteralPath $Dll -Destination $d -Force -ErrorAction Stop
  if ((Sha $d) -ne $Pin) { throw "renderer hash mismatch: $d" }
}

function Run-Native([string]$exe, [string[]]$argList, [string]$log) {
  & $exe @argList 2>&1 | Tee-Object -FilePath (Join-Path $Tools $log) -Append -ErrorAction Stop | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "exit $LASTEXITCODE from $exe (log $log)" }
}

function Run-Ps1([string]$file, [string[]]$argList, [string]$log) {
  Run-Native 'powershell.exe' (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $file) + $argList) $log
}

function Copy-Tree([string]$from, [string]$to, [string[]]$xf = @(), [string[]]$xd = @()) {
  Need $from
  $ra = @($from, $to, '/E', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
  if ($xf.Count) { $ra += '/XF'; $ra += $xf }
  if ($xd.Count) { $ra += '/XD'; $ra += $xd }
  & robocopy.exe @ra | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy exit ${LASTEXITCODE}: $from" }
}

try {
  Step 'preflight'
  if (-not $ScriptOverride) { throw '-ScriptOverride is required; reviewed no-delete stage dependencies must be explicit' }
  Need $ScriptOverride
  $existingRoot = Test-Path -LiteralPath $Root
  if ($existingRoot -and -not $Resume) { throw "Root exists, refusing to reuse without -Resume: $Root" }
  if ($Resume -and -not $existingRoot) { throw "-Resume requires existing root: $Root" }
  if ($Commit -notmatch '^[0-9a-fA-F]{7,40}$') { throw "bad -Commit: $Commit" }
  [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'BelowNormal'
  $env:Path = "$SwiftRuntime;$env:Path"
  New-Item -ItemType Directory -Force -Path $Root, $Tools -ErrorAction Stop | Out-Null

  Step 'renderer-hash'
  if ((Sha $RendererDll) -ne $Pin) { throw "renderer hash mismatch: $RendererDll" }
  New-Item -ItemType Directory -Force -Path $Rend -ErrorAction Stop | Out-Null
  Copy-Item -LiteralPath $RendererDll -Destination $Dll -Force -ErrorAction Stop
  if ((Sha $Dll) -ne $Pin) { throw "renderer hash mismatch after copy: $Dll" }

  Step 'clone'
  if ($Resume) {
    Need (Join-Path $Src '.git')
  } else {
    Run-Native 'git' @('clone', $Repo, $Src) 'clone.log'
    Run-Native 'git' @('-C', $Src, 'checkout', '--detach', $Commit) 'checkout.log'
  }
  $headLines = @(& git -C $Src rev-parse HEAD 2>&1)
  $headExit = $LASTEXITCODE
  if ($headExit -ne 0) { throw "git rev-parse failed (exit $headExit)" }
  $head = ($headLines -join "`n").Trim()
  if (-not $head.StartsWith($Commit.ToLower())) { throw "HEAD $head is not $Commit" }
  $statusLines = @(& git -C $Src status --porcelain --untracked-files=no 2>&1)
  $statusExit = $LASTEXITCODE
  if ($statusExit -ne 0) { throw "git status failed (exit $statusExit)" }
  if ($statusLines) { throw 'tracked changes in clone' }

  Step 'build-fresh'
  Put-Dll (Join-Path $Src 'payload\bin')
  Run-Ps1 (StageScript 'probes\sr0-s\fresh-on-bridge\scripts\build-fresh.ps1') @('-Base', $Src, '-Dll', $Dll, '-ExpectDllSha256', $Pin) 'build-fresh.log'
  Put-Dll (Join-Path $Src $RelDir)
  $fe = Join-Path (Join-Path $Src $RelDir) 'FreshOnBridge.exe'
  Need $fe

  Step 'smoke-tree'
  Copy-Tree (Join-Path $Src 'examples\BridgeSmoke') (Join-Path $Smoke 'examples\BridgeSmoke') @('result-*.txt') @('evidence')
  Copy-Tree (Join-Path $Src 'packages\SwiftRightBridge') (Join-Path $Smoke 'packages\SwiftRightBridge')
  Put-Dll (Join-Path $Smoke 'payload\bin')

  Step 'build-smoke'
  Run-Ps1 (StageScript 'examples\BridgeSmoke\scripts\build-smoke.ps1') @('-Base', $Smoke) 'build-smoke.log'
  Step 'build-pixels'
  Run-Ps1 (StageScript 'examples\BridgeSmoke\scripts\build-pixels.ps1') @('-Base', $Smoke, '-RendererSrc', (Join-Path $Smoke 'payload\bin\swiftright_render.dll'), '-RendererSha', $PinLower) 'build-pixels.log'
  Put-Dll (Join-Path $Smoke $RelDir)
  Put-Dll (Join-Path $Smoke 'bin')
  Need (Join-Path (Join-Path $Smoke $RelDir) 'BridgeSmoke.exe')
  Need (Join-Path $Smoke 'bin\BridgePixels.exe')

  Step 'workload-tree'
  $wsrc = Join-Path $Src 'probes\sr0-b\workload'
  $wd = Join-Path $Work 'probes\sr0-b\workload'
  foreach ($d in 'scripts', 'analysis', 'Sources') { Copy-Tree (Join-Path $wsrc $d) (Join-Path $wd $d) }
  New-Item -ItemType Directory -Force -Path $wd | Out-Null
  Copy-Item -LiteralPath (Join-Path $wsrc 'Package.swift') -Destination $wd -Force -ErrorAction Stop
  Copy-Tree (Join-Path $Src 'probes\sr0-s\fresh-runtime') (Join-Path $Work 'probes\sr0-s\fresh-runtime')
  Copy-Tree (Join-Path $Src 'packages\SwiftRightBridge') (Join-Path $Work 'packages\SwiftRightBridge')
  Copy-Tree (Join-Path $Src 'render\swiftright-abi\include') (Join-Path $Work 'render\swiftright-abi\include')
  Set-Content -LiteralPath (Join-Path $Work 'SOURCE-HEAD.txt') -Value $head -Encoding ASCII -ErrorAction Stop
  Put-Dll (Join-Path $Work 'payload\bin')

  Step 'build-workload'
  Run-Ps1 (StageScript 'probes\sr0-b\workload\scripts\build-workload.ps1') @('-Base', $Work, '-Dll', (Join-Path $Work 'payload\bin\swiftright_render.dll'), '-ExpectDllSha256', $Pin, '-VerifyManifestScript', (StageScript 'probes\sr0-b\workload\scripts\verify-manifest.ps1')) 'build-workload.log'
  Put-Dll (Join-Path $Work $RelDir)
  $we = Join-Path (Join-Path $Work $RelDir) 'WorkloadWin.exe'
  Need $we
  $bjPath = Join-Path $Work 'build.json'
  $bj = Get-Content -LiteralPath $bjPath -Raw | ConvertFrom-Json
  $bj | Add-Member -NotePropertyName staged_from -NotePropertyValue $Src -Force
  $bj | Add-Member -NotePropertyName staged_utc -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force
  $bj | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $bjPath -Encoding ASCII -ErrorAction Stop

  Step 'build-incremental'
  $wsScreen = @(Get-ChildItem -LiteralPath $wd -Recurse -Filter 'WorkloadScreen.swift' -File)
  if ($wsScreen.Count -ne 1) { throw "expected one WorkloadScreen.swift, found $($wsScreen.Count)" }
  $wsPath = $wsScreen[0].FullName
  $wsBefore = Sha $wsPath
  Run-Ps1 (StageScript 'probes\sr0-b\workload\scripts\build-incremental.ps1') @('-Base', $Work) 'build-incremental.log'
  if ((Sha $wsPath) -ne $wsBefore) { throw 'WorkloadScreen.swift not restored after incremental build' }

  Step 'geomodal-tree'
  Copy-Tree (Join-Path $Src 'examples\BridgeGeoModal') (Join-Path $Geo 'examples\BridgeGeoModal') @('result-*.txt') @('evidence')
  Copy-Tree (Join-Path $Src 'packages\SwiftRightBridge') (Join-Path $Geo 'packages\SwiftRightBridge')
  Put-Dll (Join-Path $Geo 'payload\bin')

  Step 'build-geomodal'
  Run-Ps1 (StageScript 'examples\BridgeGeoModal\scripts\build.ps1') @('-Base', $Geo, '-RendererSrc', $Dll, '-RendererSha', $PinLower) 'build-geomodal.log'
  Put-Dll (Join-Path $Geo $RelDir)
  Put-Dll (Join-Path $Geo 'bin')
  foreach ($e in 'TextGeom06', 'Modal06', 'ColdOpen06') {
    $from = Join-Path (Join-Path $Geo $RelDir) "$e.exe"
    Need $from
    Copy-Item -LiteralPath $from -Destination (Join-Path $Geo 'bin') -Force -ErrorAction Stop
  }

  Step 'slice-check'
  Run-Ps1 (StageScript 'examples\SliceApp\scripts\build-windows.ps1') @('-Base', $Src) 'slice-check.log'
  Need (Join-Path $Src 'examples\SliceApp\.build\payload\SliceApp.exe')

  Step 'verify'
  $feSha = Sha $fe
  $weSha = Sha $we
  Run-Ps1 (StageScript 'probes\sr0-s\fresh-on-bridge\scripts\verify-artifacts.ps1') @('-Base', $Src, '-ExpectExe', $feSha, '-ExpectDll', $Pin) 'verify-fresh-artifacts.log'
  Run-Ps1 (StageScript 'probes\sr0-s\fresh-on-bridge\scripts\verify-manifest.ps1') @('-Base', $Src) 'verify-fresh-manifest.log'
  Run-Ps1 (StageScript 'probes\sr0-b\workload\scripts\verify-artifacts.ps1') @('-Base', $Work, '-ExpectExe', $weSha, '-ExpectDll', $Pin) 'verify-workload-artifacts.log'
  Run-Ps1 (StageScript 'probes\sr0-b\workload\scripts\verify-manifest.ps1') @('-Base', $Work) 'verify-workload-manifest.log'
  $bj = Get-Content -LiteralPath $bjPath -Raw | ConvertFrom-Json
  if ($bj.exe_sha256 -ne $weSha) { throw 'build.json exe_sha256 does not match WorkloadWin.exe' }
  if (-not $head.StartsWith("$($bj.source_head)")) { throw 'build.json source_head does not match clone HEAD' }
  Write-Output 'NOTE smoke and geomodal have no verify script; hash checks only (dryrun not run)'

  Step 'report'
  $members = @(
    @('renderer', $Dll),
    @('FreshOnBridge', $fe),
    @('BridgeSmoke', (Join-Path (Join-Path $Smoke $RelDir) 'BridgeSmoke.exe')),
    @('BridgePixels', (Join-Path $Smoke 'bin\BridgePixels.exe')),
    @('WorkloadWin', $we),
    @('TextGeom06', (Join-Path $Geo 'bin\TextGeom06.exe')),
    @('Modal06', (Join-Path $Geo 'bin\Modal06.exe')),
    @('ColdOpen06', (Join-Path $Geo 'bin\ColdOpen06.exe'))
  )
  foreach ($m in $members) {
    Write-Output ('MEMBER {0} {1} {2}' -f $m[0], (Sha $m[1]), $m[1])
  }
  Write-Output 'STAGE_OK'
}
catch {
  Write-Output "STAGE_FAILED step=$($script:Step): $($_.Exception.Message)"
  throw
}
