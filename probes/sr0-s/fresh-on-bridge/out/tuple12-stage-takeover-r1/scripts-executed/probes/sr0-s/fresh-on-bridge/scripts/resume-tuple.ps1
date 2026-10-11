<#
Resume or restart tuple 12 staging without deleting partial tree. Build-only; no GUI or scheduled task.
Run audit-tuple.ps1 first, then run this script only after Dell process/task/lock audit is clear.
#>
param(
  [string]$Root = 'D:\Claude\swiftright\.work\sr0-r12',
  [string]$RetryRoot = 'D:\Claude\swiftright\.work\sr0-r12-retry',
  [string]$Commit = '0e201571e4320a3b6ccce14313fd2ad67e523904',
  [string]$RendererDll = 'D:\.rightkit-managed\rightkit-build-control\ws\864173e69427\g\001\target\x86_64-pc-windows-msvc\release\swiftright_render.dll',
  [string]$ExpectRenderer = 'C62B554B4B2545B8BE2429C2530E17B8C8B78DF97E67172B627E8CD18A5FE68F',
  [string]$ScriptOverride = '',
  [switch]$Restart
)
$ErrorActionPreference = 'Stop'
if (-not $ScriptOverride) { throw '-ScriptOverride is required; reviewed no-delete stage dependencies must be explicit' }
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$stage = Join-Path $here 'stage-tuple.ps1'
if (-not (Test-Path -LiteralPath $stage -PathType Leaf)) { throw "missing stage script: $stage" }
if ((Get-FileHash -LiteralPath $RendererDll -Algorithm SHA256).Hash.ToUpper() -ne $ExpectRenderer.ToUpper()) { throw 'renderer source hash mismatch' }
$lock = 'D:\Claude\desktop.lock'
if (Test-Path -LiteralPath $lock -PathType Leaf) {
  $lockText = ([IO.File]::ReadAllText($lock)).Trim()
  $lockState = $lockText
  try {
    $lockJson = $lockText | ConvertFrom-Json
    if ($lockJson -is [string]) { $lockState = [string]$lockJson }
    else { foreach ($k in 'state', 'status', 'value') { if ($lockJson.PSObject.Properties.Name -contains $k) { $lockState = [string]$lockJson.$k; break } } }
  } catch { }
  if ($lockState.Trim().ToLowerInvariant() -ne 'free') { throw "desktop lock is not free: $lock" }
}
$selfPid = [Diagnostics.Process]::GetCurrentProcess().Id
$busy = @(Get-CimInstance Win32_Process | Where-Object { $_.ProcessId -ne $selfPid -and $_.CommandLine -match 'stage-tuple|resume-tuple|sr0-r12' })
if ($busy.Count) { throw "matching stage process already exists: $($busy[0].ProcessId)" }
$target = $Root
$resume = $false
if ($Restart) {
  if (Test-Path -LiteralPath $RetryRoot) { throw "retry root exists; refusing reuse: $RetryRoot" }
  $target = $RetryRoot
} else {
  if (Test-Path -LiteralPath (Join-Path $Root 'src\.git')) {
    $resume = $true
  } elseif (-not (Test-Path -LiteralPath $Root)) {
    # Absent root is safe fresh staging at canonical tuple path; no retry sibling needed.
    $resume = $false
  } else {
    throw "partial root lacks clean source clone; rerun with -Restart: $Root"
  }
}
$args = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$stage,'-Commit',$Commit,'-Root',$target,'-RendererDll',$RendererDll,'-ExpectRenderer',$ExpectRenderer)
if ($ScriptOverride) { $args += @('-ScriptOverride', $ScriptOverride) }
if ($resume) { $args += '-Resume' }
& powershell.exe @args
if ($LASTEXITCODE -ne 0) { throw "stage script exited $LASTEXITCODE" }
