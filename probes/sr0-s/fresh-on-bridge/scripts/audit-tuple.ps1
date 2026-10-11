<#
Read-only audit for a stopped SR0 staging tree. It never starts, stops, writes or deletes.
Capture output on Dell before resuming stage-tuple.ps1.
#>
param(
  [string]$Root = 'D:\Claude\swiftright\.work\sr0-r12',
  [string]$Commit = '0e201571e4320a3b6ccce14313fd2ad67e523904',
  [string]$ExpectRenderer = 'C62B554B4B2545B8BE2429C2530E17B8C8B78DF97E67172B627E8CD18A5FE68F',
  [string]$RendererDll = 'D:\.rightkit-managed\rightkit-build-control\ws\864173e69427\g\001\target\x86_64-pc-windows-msvc\release\swiftright_render.dll'
)
$ErrorActionPreference = 'Continue'
function Hash([string]$p) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { return 'MISSING' }
  try { return (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToUpper() } catch { return "ERROR:$($_.Exception.Message)" }
}
function Say([string]$s) { Write-Output $s }
function Tool([string]$name, [string[]]$toolArguments = @('--version')) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $cmd) { Say "TOOL name=$name missing"; return }
  $lines = @(& $cmd.Source @toolArguments 2>&1)
  $rc = $LASTEXITCODE
  Say ("TOOL name={0} path={1} exit={2} version={3}" -f $name,$cmd.Source,$rc,(($lines -join ' ') -replace '\s+',' ').Trim())
}
Say "AUDIT_BEGIN utc=$([DateTime]::UtcNow.ToString('o'))"
Say "ROOT $Root"
Say "EXPECTED_COMMIT $Commit"
Say "EXPECTED_RENDERER $($ExpectRenderer.ToUpper())"

$lock = 'D:\Claude\desktop.lock'
if (Test-Path -LiteralPath $lock -PathType Leaf) { Say "DESKTOP_LOCK value=$(([IO.File]::ReadAllText($lock)).Trim() -replace '\s+',' ') path=$lock" }
else { Say "DESKTOP_LOCK missing path=$lock" }

try {
  $selfPid = [Diagnostics.Process]::GetCurrentProcess().Id
  $ps = @(Get-CimInstance Win32_Process | Where-Object {
    $_.ProcessId -ne $selfPid -and $_.CommandLine -match 'stage-tuple|sr0-r12|FreshOnBridge|BridgeSmoke|BridgePixels|WorkloadWin|TextGeom06|Modal06|ColdOpen06|swiftc|cargo|rustc|robocopy'
  })
  if ($ps.Count -eq 0) { Say 'PROCESS none matching SR0 stage/build patterns' }
  foreach ($p in $ps) { Say ("PROCESS pid={0} ppid={1} name={2} cmd={3}" -f $p.ProcessId,$p.ParentProcessId,$p.Name,($p.CommandLine -replace '\s+',' ')) }
} catch { Say "PROCESS_QUERY error=$($_.Exception.Message)" }

try {
  $tasks = @(Get-ScheduledTask | Where-Object { $_.TaskName -match 'SR0|SwiftRight|FreshOnBridge|BridgeSmoke|Workload|GeomModal' })
  if ($tasks.Count -eq 0) { Say 'TASKS none matching SR0 patterns' }
  foreach ($t in $tasks) { Say "TASK name=$($t.TaskName) state=$($t.State) path=$($t.TaskPath)" }
} catch { Say "TASK_QUERY error=$($_.Exception.Message)" }

if (-not (Test-Path -LiteralPath $Root -PathType Container)) { Say "ROOT_MISSING $Root" }
$src = Join-Path $Root 'src'
if (Test-Path -LiteralPath (Join-Path $src '.git')) {
  $head = (& git -C $src rev-parse HEAD 2>$null).Trim()
  $dirty = (& git -C $src status --porcelain --untracked-files=no 2>$null) -join ' '
  Say "SOURCE_HEAD $head"
  Say "SOURCE_EXPECTED match=$($head.StartsWith($Commit.ToLower()))"
  Say "SOURCE_TRACKED_DIRTY $([bool]$dirty)"
} else { Say "SOURCE_GIT missing path=$src" }

Say "RENDERER_SOURCE path=$RendererDll sha256=$(Hash $RendererDll)"
foreach ($p in @(
  'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin\swift.exe',
  'C:\Program Files (x86)\Windows Kits\10\bin',
  'C:\Program Files\Microsoft Visual Studio'
)) { Say "TOOL_PATH path=$p present=$(Test-Path -LiteralPath $p)" }
Tool 'git'
Tool 'swift'
$members = @(
  @('renderer', (Join-Path $Root 'renderer\swiftright_render.dll')),
  @('FreshOnBridge', (Join-Path $Root 'src\scratch\out\Products\Release-windows-x86_64\FreshOnBridge.exe')),
  @('BridgeSmoke', (Join-Path $Root 'smoke\scratch\out\Products\Release-windows-x86_64\BridgeSmoke.exe')),
  @('BridgePixels', (Join-Path $Root 'smoke\bin\BridgePixels.exe')),
  @('WorkloadWin', (Join-Path $Root 'workload\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe')),
  @('TextGeom06', (Join-Path $Root 'geomodal\bin\TextGeom06.exe')),
  @('Modal06', (Join-Path $Root 'geomodal\bin\Modal06.exe')),
  @('ColdOpen06', (Join-Path $Root 'geomodal\bin\ColdOpen06.exe'))
)
foreach ($m in $members) { Say ("MEMBER {0} sha256={1} path={2}" -f $m[0],(Hash $m[1]),$m[1]) }

foreach ($f in @('SOURCE-HEAD.txt','build.json','incremental.json')) {
  $hits = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $f -ErrorAction SilentlyContinue)
  foreach ($h in $hits) { Say ("RECEIPT {0} bytes={1} sha256={2}" -f $h.FullName,$h.Length,(Hash $h.FullName)) }
}
$logs = @(Get-ChildItem -LiteralPath (Join-Path $Root 'stage-tools') -File -ErrorAction SilentlyContinue)
foreach ($l in $logs) { Say ("STAGE_LOG {0} bytes={1} sha256={2}" -f $l.FullName,$l.Length,(Hash $l.FullName)); Get-Content -LiteralPath $l.FullName -Tail 8 | ForEach-Object { Say "  $_" } }
Say 'BROKER_STATUS required from root Mac session; this script does not contact broker'
Say 'AUDIT_END'
if (-not (Test-Path -LiteralPath $Root -PathType Container)) { exit 2 }
