# Tuple12 root-owned workload display scheduler source packet.
# Root runs this from elevated interactive desktop session after source controls.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Root,
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$OutRoot,
  [string]$ControlRoot,
  [string]$AnalysisRoot,
  [string]$Lock = 'D:\Claude\desktop.lock',
  [string]$Tag = '',
  [string]$TaskName = ''
)
$ErrorActionPreference = 'Stop'
$Root = [IO.Path]::GetFullPath($Root)
if (-not $ControlRoot) { $ControlRoot = Join-Path $Root 'qualification\tuple12-takeover\workload-controls-v8' }
if (-not $AnalysisRoot) { $AnalysisRoot = Join-Path $Root 'qualification\tuple12-takeover\workload-analysis-v3' }
if (-not $Tag) { $Tag = 'tuple12-display-root-' + [guid]::NewGuid().ToString('N') }
if (-not $TaskName) { $TaskName = 'SR0-' + $Tag }
if ($Tag -notmatch '^[A-Za-z0-9._-]+$' -or $TaskName -notmatch '^[A-Za-z0-9._-]+$') { throw 'unsafe tag/task name' }
$envelope = Join-Path $Root 'qualification\tuple12-takeover\workload-display-root-launch-v1\run-display-root-launch-v1.ps1'
$child = Join-Path $Root 'qualification\tuple12-takeover\workload-display-diagnostic-v3\run-one-diagnostic.ps1'
$helper = Join-Path $Root 'qualification\tuple12-takeover\workload-incremental-v6\shared\Sr0OwnedJobProcess.cs'
$control = Join-Path $Root 'qualification\tuple12-takeover\workload-controls-v8'
$analysis = Join-Path $Root 'qualification\tuple12-takeover\workload-analysis-v3'
foreach ($path in @($envelope,$child,$helper,$control,$analysis,$Base)) {
  if (-not (Test-Path -LiteralPath $path)) { throw "required source/path missing: $path" }
}
$exe = '7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c'
$dll = '7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Q([string]$value) { '"' + $value.Replace('"','\"') + '"' }
$arg = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File ' + (Q $envelope) +
  ' -Base ' + (Q $Base) + ' -ControlRoot ' + (Q $ControlRoot) +
  ' -AnalysisRoot ' + (Q $AnalysisRoot) + ' -OutRoot ' + (Q $OutRoot) +
  ' -ExpectExe ' + $exe + ' -ExpectDll ' + $dll + ' -Lock ' + (Q $Lock) +
  ' -Tag ' + (Q $Tag) + ' -ChildScriptPath ' + (Q $child) + ' -HelperPath ' + (Q $helper)
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { throw "task already exists: $TaskName" }
$action = New-ScheduledTaskAction -Execute $ps -Argument $arg -WorkingDirectory $Root
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings | Out-Null
Start-ScheduledTask -TaskName $TaskName
[ordered]@{ kind='sr0-tuple12-workload-display-root-launch-v1'; taskName=$TaskName; taskPrincipal='interactive-highest'; envelope=$envelope; child=$child; helper=$helper; controlRoot=$ControlRoot; analysisRoot=$AnalysisRoot; base=$Base; output=$OutRoot; exeSha256=$exe; rendererSha256=$dll; memoryLimitBytes=1073741824; memoryLimitFlags='0x200'; killOnJobClose=$false; parentHandleRetained=$true; childProof='terminal, drained streams, activeProcesses=0, task quiescence, lockReleased'; nativeActions=0 } | ConvertTo-Json -Depth 8
