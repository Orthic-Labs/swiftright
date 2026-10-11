# Tuple12 F1 smoke coordinator. Holds desktop.lock through one hidden interactive task; never deletes task or output.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$Worker,
  [Parameter(Mandatory)][string]$Driver,
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll,
  [Parameter(Mandatory)][string]$OutRoot,
  [string]$Lock = 'D:\Claude\desktop.lock'
)
$ErrorActionPreference = 'Stop'
$expectedExe = $ExpectExe.ToLowerInvariant(); $expectedDll = $ExpectDll.ToLowerInvariant()
if ($expectedExe -notmatch '^[0-9a-f]{64}$' -or $expectedDll -notmatch '^[0-9a-f]{64}$') { throw 'expected artifact hash is not SHA-256' }
$runId = [guid]::NewGuid().ToString('N')
$runRoot = Join-Path $OutRoot ('F1-r1-' + $runId)
$receipt = Join-Path $OutRoot ('receipts\worker-' + $runId + '.json')
$label = 'SR0-T12-F1-' + $runId
$lockOwner = "$label $([DateTimeOffset]::UtcNow.ToString('o'))"
$taskName = 'SR0-T12-F1-' + $runId
$lockHeld = $false; $releaseAllowed = $false; $lockReleased = $false; $releaseError = $null
$proof = $null; $failureText = $null; $state = $null; $info = $null; $terminalProof = $false; $taskQuiescent = $false; $semanticPass = $false
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
  if ((Test-Path -LiteralPath $runRoot -PathType Container) -or (Test-Path -LiteralPath $receipt -PathType Leaf)) { throw 'generated smoke namespace already exists' }
  [IO.Directory]::CreateDirectory($OutRoot) | Out-Null
  while (-not (Try-Acquire)) { Start-Sleep -Seconds 20 }
  $lockHeld = $true
  $workerArgs = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File {0} -Base {1} -Driver {2} -ExpectExe {3} -ExpectDll {4} -RunRoot {5} -Receipt {6}' -f (Quote-Arg ([IO.Path]::GetFullPath($Worker))), (Quote-Arg ([IO.Path]::GetFullPath($Base))), (Quote-Arg ([IO.Path]::GetFullPath($Driver))), (Quote-Arg $expectedExe), (Quote-Arg $expectedDll), (Quote-Arg ([IO.Path]::GetFullPath($runRoot))), (Quote-Arg ([IO.Path]::GetFullPath($receipt)))
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
    $terminalProof = ($proof.driverKernel.terminal -and $proof.driverKernel.getExitCode -and $proof.childKernel.terminal -and $proof.childKernel.getExitCode -and $proof.driverHandle.retained -and $proof.childHandle.retained -and ([IO.Path]::GetFullPath([string]$proof.childPath) -ceq $expectedChildPath) -and ([string]$proof.exe.sha256 -ceq $expectedExe) -and ([string]$proof.renderer.sha256 -ceq $expectedDll))
    $releaseAllowed = ($terminalProof -and $taskQuiescent)
    if (-not $releaseAllowed) { throw "terminal proof failed task=$state result=$($info.LastTaskResult) kernel=$terminalProof quiescent=$taskQuiescent" }
    $semanticPass = ($info.LastTaskResult -eq 0 -and $proof.status -eq 'passed' -and $proof.workerExitCode -eq 0 -and $proof.driverExitCode -eq 0 -and $proof.childExitCode -eq 0)
    if (-not $semanticPass) { throw "F1 semantic proof failed; lock release is safe task=$state result=$($info.LastTaskResult)" }
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
  [ordered]@{ kind = 'sr0-tuple12-startupguard-f1-terminal-v1'; status = $statusText; lockOwner = $lockOwner; lockReleased = $lockReleased; taskName = $taskName; receipt = $receipt; runRoot = $runRoot; taskState = $state; terminalProof = $terminalProof; taskQuiescent = $taskQuiescent; failure = $failureText; releaseError = $releaseError } | ConvertTo-Json -Depth 8 | Write-Output
}
exit 0
