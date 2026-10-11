# Tuple12 candidate matrix coordinator. Holds desktop.lock through one hidden interactive task; never deletes task or output.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Worker,
  [Parameter(Mandatory)][string]$Driver,
  [Parameter(Mandatory)][string]$ExpectDriver,
  [Parameter(Mandatory)][string]$ExpectWorker,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [Parameter(Mandatory)][string]$OutRoot,
  [ValidateSet('F1','F2','F3','F4','F5','F6','F7','F8','F9')][string]$Fixture = 'F1',
  [string]$Variant = '',
  [ValidateSet('char')][string]$KeyMode = 'char',
  [string]$Lock = 'D:\Claude\desktop.lock'
)
$ErrorActionPreference = 'Stop'
$expectedDriver = $ExpectDriver.ToLowerInvariant(); $expectedWorker = $ExpectWorker.ToLowerInvariant()
$expectedExe = $ExpectExe.ToLowerInvariant(); $expectedDll = $ExpectDll.ToLowerInvariant()
if (@($expectedDriver,$expectedWorker,$expectedExe,$expectedDll) | Where-Object { $_ -notmatch '^[0-9a-f]{64}$' }) { throw 'expected source/artifact hash is not SHA-256' }
$runId = [guid]::NewGuid().ToString('N')
$variantSlug = if ($Variant) { '-' + ($Variant -replace '[^A-Za-z0-9]+','-') } else { '' }
$runRoot = Join-Path $OutRoot ($Fixture + $variantSlug + '-r-' + $runId)
$receipt = Join-Path $OutRoot ('receipts\worker-' + $runId + '.json')
$label = 'SR0-T12-MX-' + $Fixture + $variantSlug + '-' + $runId
$lockOwner = "$label $([DateTimeOffset]::UtcNow.ToString('o'))"
$taskName = 'SR0-T12-' + $Fixture + $variantSlug + '-' + $runId
$lockHeld = $false; $releaseAllowed = $false; $lockReleased = $false; $releaseError = $null
$proof = $null; $failureText = $null; $state = $null; $info = $null; $terminalProof = $false; $taskQuiescent = $false; $semanticPass = $false
$sourcePins = [ordered]@{ base = $Base; driver = $Driver; worker = $Worker; expectedDriver = $expectedDriver; expectedWorker = $expectedWorker; actualDriver = $null; actualWorker = $null }
$terminalChecks = [ordered]@{}
function Quote-Arg([string]$v) { return '"' + $v.Replace('"', '\"') + '"' }
function Quote-Vbs([string]$v) { return '"' + $v.Replace('"', '""') + '"' }
function Lock-Text([IO.FileStream]$fs) {
  $fs.Position = 0; $buf = New-Object byte[] ([int]$fs.Length); if ($buf.Length) { [void]$fs.Read($buf,0,$buf.Length) }; return [Text.Encoding]::UTF8.GetString($buf).Trim()
}
function Lock-IsFree([string]$text) {
  if ($text -eq 'free') { return $true }
  try { $o = $text | ConvertFrom-Json; foreach ($k in @('state','status','value')) { if ($o.PSObject.Properties.Name -contains $k -and [string]$o.$k -eq 'free') { return $true } } } catch {}
  return $false
}
function Try-Acquire {
  try {
    $fs = [IO.File]::Open($Lock, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
      if (-not (Lock-IsFree (Lock-Text $fs))) { return $false }
      $bytes = [Text.Encoding]::UTF8.GetBytes("$lockOwner`r`n")
      $fs.SetLength(0); $fs.Position = 0; $fs.Write($bytes,0,$bytes.Length); $fs.Flush($true)
      return $true
    } finally { $fs.Dispose() }
  } catch [IO.IOException] { return $false }
}
function Release-Lock {
  $fs = [IO.File]::Open($Lock, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
  try {
    if ((Lock-Text $fs) -cne $lockOwner) { throw 'desktop lock ownership changed; preserving lock' }
    $bytes = [Text.Encoding]::UTF8.GetBytes("free`r`n"); $fs.SetLength(0); $fs.Position = 0; $fs.Write($bytes,0,$bytes.Length); $fs.Flush($true)
  } finally { $fs.Dispose() }
}
function Related-Process([int]$observedPid) { @(Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $observedPid) -ErrorAction SilentlyContinue) }
try {
  if (-not (Test-Path -LiteralPath $Lock -PathType Leaf)) { throw "desktop lock missing: $Lock" }
  if (-not (Test-Path -LiteralPath $Base -PathType Container)) { throw "base stage missing: $Base" }
  foreach ($path in @($Worker,$Driver)) { if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "pinned script missing: $path" } }
  $sourcePins.actualDriver = (Get-FileHash -LiteralPath $Driver -Algorithm SHA256).Hash.ToLowerInvariant()
  $sourcePins.actualWorker = (Get-FileHash -LiteralPath $Worker -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($sourcePins.actualDriver -cne $expectedDriver) { throw 'driver source hash mismatch' }
  if ($sourcePins.actualWorker -cne $expectedWorker) { throw 'worker source hash mismatch' }
  if ((Test-Path -LiteralPath $runRoot -PathType Container) -or (Test-Path -LiteralPath $receipt -PathType Leaf)) { throw 'generated smoke namespace already exists' }
  [IO.Directory]::CreateDirectory($OutRoot) | Out-Null
  while (-not (Try-Acquire)) { Start-Sleep -Seconds 20 }
  $lockHeld = $true
  $workerArgs = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File {0} -Base {1} -Driver {2} -ExpectExe {3} -ExpectDll {4} -RunRoot {5} -Receipt {6} -Fixture {7} -Variant {8} -KeyMode {9}' -f (Quote-Arg ([IO.Path]::GetFullPath($Worker))), (Quote-Arg ([IO.Path]::GetFullPath($Base))), (Quote-Arg ([IO.Path]::GetFullPath($Driver))), (Quote-Arg $expectedExe), (Quote-Arg $expectedDll), (Quote-Arg ([IO.Path]::GetFullPath($runRoot))), (Quote-Arg ([IO.Path]::GetFullPath($receipt))), $Fixture, (Quote-Arg $Variant), $KeyMode
  $launcherRoot = Join-Path $OutRoot 'launchers'
  [IO.Directory]::CreateDirectory($launcherRoot) | Out-Null
  $launcher = Join-Path $launcherRoot ($taskName + '.vbs')
  $workerCommand = 'powershell.exe ' + $workerArgs
  $vbs = "Option Explicit`r`nDim shell`r`nSet shell = CreateObject(""WScript.Shell"")`r`nshell.Run $(Quote-Vbs $workerCommand), 0, True`r`n"
  $launcherStream = [IO.File]::Open($launcher, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
  try { $bytes = [Text.Encoding]::ASCII.GetBytes($vbs); $launcherStream.Write($bytes,0,$bytes.Length); $launcherStream.Flush($true) } finally { $launcherStream.Dispose() }
  $wscript = Join-Path $env:SystemRoot 'System32\wscript.exe'
  if (-not (Test-Path -LiteralPath $wscript -PathType Leaf)) { throw "hidden task host missing: $wscript" }
  $action = New-ScheduledTaskAction -Execute $wscript -Argument ('//B //Nologo ' + (Quote-Arg $launcher)) -WorkingDirectory $Base
  $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 8)
  if ($null -ne (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue)) { throw 'generated scheduled-task name already exists' }
  Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings | Out-Null
  try {
    Start-ScheduledTask -TaskName $taskName
    $taskDeadline = [DateTime]::UtcNow.AddMinutes(7)
    do {
      Start-Sleep -Seconds 2
      $state = (Get-ScheduledTask -TaskName $taskName).State
      $done = (Test-Path -LiteralPath $receipt -PathType Leaf) -and ($state -notin @('Running','Queued'))
    } while (-not $done -and [DateTime]::UtcNow -lt $taskDeadline)
    $info = Get-ScheduledTaskInfo -TaskName $taskName
    if (-not (Test-Path -LiteralPath $receipt -PathType Leaf)) { throw "worker receipt missing; task state=$state result=$($info.LastTaskResult)" }
    $proof = [IO.File]::ReadAllText($receipt) | ConvertFrom-Json
    $related = @($proof.workerPid,$proof.driverPid,$proof.childPid) | Where-Object { $null -ne $_ -and [int64]$_ -gt 0 } | ForEach-Object { Related-Process ([int]$_) }
    $taskQuiescent = ($state -notin @('Running','Queued') -and $related.Count -eq 0)
    $expectedChildPath = [IO.Path]::GetFullPath((Join-Path $Base 'scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe'))
    $allowedWorkerKinds = @('sr0-tuple12-startupguard-matrix-worker-v3','sr0-tuple12-startupguard-matrix-worker-v4','sr0-tuple12-startupguard-matrix-worker-v5')
    $childPathExact = $false
    try {
      $childPathValue = [string]$proof.childPath
      if (-not [string]::IsNullOrWhiteSpace($childPathValue)) { $childPathExact = ([IO.Path]::GetFullPath($childPathValue) -ceq $expectedChildPath) }
    } catch { $childPathExact = $false }
    $terminalChecks = [ordered]@{
      workerKind = ($allowedWorkerKinds -contains [string]$proof.kind)
      driverKernelTerminal = ($proof.driverKernel.terminal -eq $true)
      driverKernelExitCodeReadable = ($proof.driverKernel.getExitCode -eq $true)
      childKernelTerminal = ($proof.childKernel.terminal -eq $true)
      childKernelExitCodeReadable = ($proof.childKernel.getExitCode -eq $true)
      driverHandleRetained = ($proof.driverHandle.retained -eq $true)
      childHandleRetained = ($proof.childHandle.retained -eq $true)
      childPathExact = $childPathExact
      driverSourceHashExact = ([string]$proof.driverScript.sha256 -ceq $expectedDriver)
      exeHashExact = ([string]$proof.exe.sha256 -ceq $expectedExe)
      rendererHashExact = ([string]$proof.renderer.sha256 -ceq $expectedDll)
    }
    $terminalProof = (@($terminalChecks.Values | Where-Object { $_ -ne $true }).Count -eq 0)
    $releaseAllowed = ($terminalProof -and $taskQuiescent)
    if (-not $releaseAllowed) { throw "terminal proof failed task=$state result=$($info.LastTaskResult) kernel=$terminalProof quiescent=$taskQuiescent" }
    $semanticPass = ($info.LastTaskResult -eq 0 -and $proof.status -eq 'passed' -and $proof.workerExitCode -eq 0 -and $proof.driverExitCode -eq 0 -and $proof.childExitCode -eq 0)
    if (-not $semanticPass) { throw "$Fixture$variantSlug semantic proof failed; lock release is safe task=$state result=$($info.LastTaskResult)" }
  } finally {
    Disable-ScheduledTask -TaskName $taskName | Out-Null
  }
} catch {
  $failureText = $_.Exception.Message
  throw
} finally {
  if ($lockHeld -and $releaseAllowed) {
    try { Release-Lock; $lockReleased = $true } catch { $releaseError = $_.Exception.Message }
  }
  $semanticStatus = ($lockReleased -and $semanticPass -and $null -eq $releaseError)
  $statusText = if ($semanticStatus) { 'passed' } else { 'failed' }
  [ordered]@{ kind = 'sr0-tuple12-startupguard-matrix-terminal-v5'
  fixture = $Fixture
  variant = $Variant
  keyMode = $KeyMode; status = $statusText; lockOwner = $lockOwner; lockReleased = $lockReleased; taskName = $taskName; receipt = $receipt; runRoot = $runRoot; taskState = $state; terminalProof = $terminalProof; terminalChecks = $terminalChecks; taskQuiescent = $taskQuiescent; sourcePins = $sourcePins; failure = $failureText; releaseError = $releaseError } | ConvertTo-Json -Depth 8 | Write-Output
}
exit 0
