# Tuple12 candidate matrix runner. Requires admitted noactivate F1 smoke before any matrix task.
# It preserves every output/task, uses targeted delivery, & never unregisters scheduled tasks.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Driver,
  [Parameter(Mandatory)][string]$Worker,
  [Parameter(Mandatory)][string]$Coordinator,
  [Parameter(Mandatory)][string]$ExpectWorker,
  [Parameter(Mandatory)][string]$ExpectCoordinator,
  [Parameter(Mandatory)][string]$SmokeReceipt,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [Parameter(Mandatory)][string]$ExpectDriver,
  [Parameter(Mandatory)][string]$OutRoot,
  [ValidateSet('F1','Full')][string]$Mode = 'F1',
  [ValidateSet(20)][int]$Runs = 20,
  [string]$Lock = 'D:\Claude\desktop.lock'
)
$ErrorActionPreference = 'Stop'
$expectedExe = $ExpectExe.ToLowerInvariant(); $expectedDll = $ExpectDll.ToLowerInvariant(); $expectedDriver = $ExpectDriver.ToLowerInvariant(); $expectedWorker = $ExpectWorker.ToLowerInvariant(); $expectedCoordinator = $ExpectCoordinator.ToLowerInvariant()
foreach ($name in @('ExpectExe','ExpectDll','ExpectDriver','ExpectWorker','ExpectCoordinator')) {
  $value = Get-Variable -Name $name -ValueOnly
  if ($value -notmatch '^[0-9a-f]{64}$') { throw "$name is not SHA-256" }
}
function Full-Leaf([string]$path) {
  $item = Get-Item -LiteralPath $path -ErrorAction Stop
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "reparse-point input rejected: $path" }
  return $item.FullName
}
function Hash-Lower([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Write-Exclusive([string]$path, [string]$text) {
  if (Test-Path -LiteralPath $path) { throw "output exists: $path" }
  $stream = [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try { $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($text); $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}
function Assert-Receipt([string]$path, [bool]$smoke) {
  $r = [IO.File]::ReadAllText($path) | ConvertFrom-Json
  if ([string]$r.kind -notin @('sr0-tuple12-startupguard-matrix-worker-v2','sr0-tuple12-startupguard-matrix-worker-v3')) { throw "unexpected worker receipt kind: $path" }
  if ($r.status -ne 'passed' -or $r.workerExitCode -ne 0 -or $r.driverExitCode -ne 0 -or $r.childExitCode -ne 0) { throw "receipt is not admitted: $path" }
  if (-not $r.driverScript -or $r.driverScript.sha256.ToLowerInvariant() -cne $expectedDriver) { throw "driver receipt hash mismatch: $path" }
  if ($r.exe.sha256.ToLowerInvariant() -cne $expectedExe -or $r.renderer.sha256.ToLowerInvariant() -cne $expectedDll) { throw "artifact receipt hash mismatch: $path" }
  if (-not $r.driverKernel.terminal -or -not $r.childKernel.terminal -or -not $r.driverHandle.retained -or -not $r.childHandle.retained) { throw "kernel/handle proof missing: $path" }
  return $r
}
$baseFull = Full-Leaf $Base
$driverFull = Full-Leaf $Driver
$workerFull = Full-Leaf $Worker
$coordinatorFull = Full-Leaf $Coordinator
$smokeFull = Full-Leaf $SmokeReceipt
if ((Hash-Lower $driverFull) -cne $expectedDriver) { throw 'candidate driver hash mismatch' }
if ((Hash-Lower $workerFull) -cne $expectedWorker) { throw 'candidate worker source hash mismatch' }
if ((Hash-Lower $coordinatorFull) -cne $expectedCoordinator) { throw 'candidate coordinator source hash mismatch' }
$smoke = Assert-Receipt $smokeFull $true
$bin = Join-Path $baseFull 'scratch\out\Products\Release-windows-x86_64'
$exe = Join-Path $bin 'FreshOnBridge.exe'; $dll = Join-Path $bin 'swiftright_render.dll'
if ((Hash-Lower $exe) -cne $expectedExe -or (Hash-Lower $dll) -cne $expectedDll) { throw 'candidate artifact hash mismatch before matrix' }
if (Test-Path -LiteralPath $OutRoot) {
  if (-not (Get-Item -LiteralPath $OutRoot).PSIsContainer) { throw 'OutRoot exists and is not directory' }
  $existing = @(Get-ChildItem -LiteralPath $OutRoot -Force)
  if ($existing.Count -ne 0) { throw 'OutRoot must be fresh and empty' }
} else { [IO.Directory]::CreateDirectory($OutRoot) | Out-Null }
$configs = @(
  [pscustomobject]@{ Fixture='F1'; Variant='' }
)
if ($Mode -eq 'Full') {
  $configs = @(
    [pscustomobject]@{ Fixture='F1'; Variant='' }, [pscustomobject]@{ Fixture='F2'; Variant='' },
    [pscustomobject]@{ Fixture='F3'; Variant='list-0s' }, [pscustomobject]@{ Fixture='F3'; Variant='list-1s' },
    [pscustomobject]@{ Fixture='F3'; Variant='list-3s' }, [pscustomobject]@{ Fixture='F3'; Variant='vstack-1s' },
    [pscustomobject]@{ Fixture='F3'; Variant='vstack-3s' }, [pscustomobject]@{ Fixture='F3'; Variant='lazy-1s' },
    [pscustomobject]@{ Fixture='F3'; Variant='lazy-3s' }, [pscustomobject]@{ Fixture='F4'; Variant='' },
    [pscustomobject]@{ Fixture='F5'; Variant='' }, [pscustomobject]@{ Fixture='F6'; Variant='' },
    [pscustomobject]@{ Fixture='F6'; Variant='reduced' }, [pscustomobject]@{ Fixture='F7'; Variant='' },
    [pscustomobject]@{ Fixture='F8'; Variant='' }, [pscustomobject]@{ Fixture='F9'; Variant='' }
  )
}
$index = 0
foreach ($cfg in $configs) {
  $slug = if ($cfg.Variant) { "$($cfg.Fixture)-$($cfg.Variant)" } else { $cfg.Fixture }
  for ($run = 1; $run -le $Runs; $run++) {
    $index++
    $caseRoot = Join-Path $OutRoot ("{0}-r{1}-{2}" -f $slug,$run,[guid]::NewGuid().ToString('N'))
    if (Test-Path -LiteralPath $caseRoot) { throw "case output exists: $caseRoot" }
    [IO.Directory]::CreateDirectory($caseRoot) | Out-Null
    # Windows PowerShell drops an empty array argument. Preserve default Variant by
    # omitting its switch when empty; never let an empty value shift later switches.
    $coordinatorArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$coordinatorFull,'-Base',$baseFull,'-Worker',$workerFull,'-Driver',$driverFull,'-ExpectDriver',$expectedDriver,'-ExpectWorker',$expectedWorker,'-ExpectExe',$expectedExe,'-ExpectDll',$expectedDll,'-OutRoot',$caseRoot,'-Fixture',$cfg.Fixture,'-KeyMode','char','-Lock',$Lock)
    if ($cfg.Variant) { $coordinatorArguments += @('-Variant',$cfg.Variant) }
    $coordOutput = @(& (Join-Path $PSHOME 'powershell.exe') @coordinatorArguments 2>&1)
    $coordExit = $LASTEXITCODE
    Write-Exclusive (Join-Path $caseRoot 'coordinator-output.txt') ([string]::Join("`r`n", @($coordOutput)))
    $receipts = @(Get-ChildItem -LiteralPath $caseRoot -Filter 'worker-*.json' -File -Recurse -ErrorAction SilentlyContinue)
    if ($receipts.Count -ne 1) { throw "expected one worker receipt for $slug run $run, got $($receipts.Count)" }
    $receipt = Assert-Receipt $receipts[0].FullName $false
    if ($coordExit -ne 0) { throw "coordinator failed for $slug run $run; output preserved at $caseRoot" }
    $terminal = [ordered]@{ kind='sr0-tuple12-matrix-run-v3'; index=$index; mode=$Mode; fixture=$cfg.Fixture; variant=$cfg.Variant; run=$run; runs=$Runs; status='passed'; base=$baseFull; driver=$driverFull; driverSha256=$expectedDriver; worker=$workerFull; workerSha256=$expectedWorker; coordinator=$coordinatorFull; coordinatorSha256=$expectedCoordinator; exeSha256=$expectedExe; rendererSha256=$expectedDll; workerReceipt=$receipts[0].FullName; coordinatorExit=$coordExit; smokeReceipt=$smokeFull; targetedDelivery=$true; noActivate=$true; output=$caseRoot }
    Write-Exclusive (Join-Path $caseRoot 'matrix-run.json') (($terminal | ConvertTo-Json -Depth 10))
    Write-Output ("PASS {0} run={1}/{2} output={3}" -f $slug,$run,$Runs,$caseRoot)
  }
}
Write-Output ("MATRIX_PASS mode={0} configs={1} runs={2} total={3} smoke={4}" -f $Mode,$configs.Count,$Runs,$index,$smokeFull)
