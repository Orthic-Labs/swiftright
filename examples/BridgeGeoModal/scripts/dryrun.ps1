# Dry run for rows 6 and 7: nothing here opens a window, touches the desktop or sends input.
#  1. artifact check (renderer == the pinned final tuple, exe hashes printed)
#  2. PowerShell parse check of every script, and the driver self-tests (-DryRun)
#  3. each host exe with SWR_GM_DRYRUN=1: the pure-logic self-test and an explicit LoadLibraryW of the renderer with
#     bootstrap validation (ABI 0.6, struct sizes, function count) and the ComCtl v6 manifest effect, but NO swr_run
#  4. no leftover scheduled task of these drivers
# -RendererSha: the expected sha256 of swiftright_render.dll when it is not the final tuple pinned in common.ps1 (modal-stall fix build).
param([string]$Base = 'D:\Claude\sr0-geomodal', [string]$Bin = '', [string]$RendererSha = '')
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $Bin) { $Bin = Join-Path $Base 'bin' }
if (-not $RendererSha) { $RendererSha = $script:PinnedRendererSha }
$fail = 0
function Step([string]$name, [bool]$ok, [string]$detail) { if (-not $ok) { $script:fail++ }; "{0} {1} [{2}]" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name, $detail }
"dryrun started=$(Get-Date -Format o) host=$env:COMPUTERNAME session=$((Get-Process -Id $PID).SessionId)"
$rsha = Get-Sha (Join-Path $Bin 'swiftright_render.dll')
Step "renderer is the expected build ($(if ($RendererSha -eq $script:PinnedRendererSha) { 'pinned final tuple' } else { 'modal-stall fix build' }))" ($rsha -eq $RendererSha.ToLower()) "$rsha expected=$($RendererSha.ToLower())"
Get-Artifacts $Bin @('TextGeom06.exe', 'Modal06.exe')
foreach ($f in Get-ChildItem (Join-Path $PSScriptRoot '*.ps1')) { $e = Test-ParseFile $f.FullName; Step "parse $($f.Name)" ($e.Count -eq 0) "errors=$($e.Count)" }
foreach ($d in 'drive-textgeom.ps1', 'drive-modal.ps1') {
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $d) -DryRun 2>&1 | Out-String
  Step "$d -DryRun" ($LASTEXITCODE -eq 0) ($o.Trim() -replace "`r?`n", ' | ')
}
foreach ($e in 'TextGeom06.exe', 'Modal06.exe') {
  $log = Join-Path $env:TEMP "$e.dryrun.log"
  Remove-Item $log -Force -ErrorAction SilentlyContinue
  $hp = Start-Host (Join-Path $Bin $e) $Bin @{ SWR_GM_DRYRUN = '1'; SWR_GM_LOG = $log }
  $ok = $hp.Proc.WaitForExit(40000)
  if (-not $ok) { try { $hp.Proc.Kill() } catch { } }
  $hp.Proc.WaitForExit()
  $txt = Read-Shared $log
  Step "$e SWR_GM_DRYRUN=1" ($ok -and $hp.Proc.ExitCode -eq 0 -and $txt -match 'DRYRUN logic PASS' -and $txt -match 'abi 0\.6 fn_count=16 stats_size=200') ("exit=$($hp.Proc.ExitCode) :: " + (($txt.Trim() -split "`r?`n") -join ' | '))
  Remove-Item $log -Force -ErrorAction SilentlyContinue
}
$left = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'SR0GM-*' })
Step 'no leftover SR0GM-* scheduled task' ($left.Count -eq 0) "found=$($left.Count)"
"dryrun $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) ended=$(Get-Date -Format o)"
exit $(if ($fail -eq 0) { 0 } else { 1 })
