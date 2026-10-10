# Dry run for rows 6 and 7: nothing here opens a window, touches the desktop or sends input.
#  1. artifact check (renderer == the pinned final tuple, exe hashes printed)
#  2. PowerShell parse check of every script, and the driver self-tests (-DryRun)
#  3. each host exe with SWR_GM_DRYRUN=1: the pure-logic self-test and an explicit LoadLibraryW of the renderer with
#     bootstrap validation (ABI 0.6, struct sizes, function count) and the ComCtl v6 manifest effect, but NO swr_run
#  4. no leftover scheduled task of these drivers
#  5. the foreground classification (Modal06 driver, tuple 08) on synthetic fg logs: foreground_lost only when every failed check sits in a modal
#     during which another process held the foreground; real failures (no loss in the failing modal, stalls, ticks, idle latency, exceptions,
#     a run-wide failure alone, no-foreground-window, teardown of the host's own window) are never excused; plus the fg.log round trip, the AX tally
#     parser and a short live run of the 10 ms foreground watch (it only polls GetForegroundWindow: no window, no input)
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

# ---- 5. foreground classification on synthetic logs
function New-FgLine([int]$T, [int]$Id, [string]$Tag, [string]$Phase, [string]$Owner, [string]$Title = '', [bool]$IsHost = $false, [bool]$HostWin = $true) {
  $procId = if ($IsHost) { 4000 } elseif ($Owner -eq 'none') { 0 } else { 5000 + $Owner.Length }
  $rec = [pscustomobject]@{ TMs = $T; Wall = ('10:00:{0:D2}.{1:D3}' -f [int][math]::Floor($T / 1000), ($T % 1000)); Hwnd = $(if ($procId -ne 0) { 1000 + $procId } else { 0 }); Pid = $procId; Owner = $Owner; Class = 'C'; Title = $Title; IsHost = $IsHost; HostWinAlive = $HostWin }
  return (Format-FgRec $rec $Id $Tag $Phase)
}
function New-FailedCheck([string]$Name, [string]$Detail) { [pscustomobject]@{ name = $Name; status = 'FAIL'; detail = $Detail } }
$cMsaa = New-FailedCheck 'S1 menu content visible through MSAA (Open, Save checked, separator, Delete disabled, Quit)' 'items=[] hr=0x80004005 ptr=0'
$cExit = New-FailedCheck 'host exited by itself with code 0' 'exit=1 killed='
$cHostS1 = New-FailedCheck 'host: S1 menu-select: async result arrives once with the expected item id and index' 'request=SWR_OK action=2 (want 2) i0=0 i1=-1 choice=none want=15/4 failed=false events=1 ticks_during=46'
$cOneOff = New-FailedCheck 'host: one-off cost of opening a modal within 50 ms (modal-loop run 8 bound)' 'max=52.19 ms over 375 jobs in the first 150 ms of each modal'
$pumpName = 'host: main loop keeps pumping while a modal is open: jobs RUN in every modal interval (counted by run time) with no long pause'
$cPumpS2 = New-FailedCheck $pumpName 'jobs run in [request+150 ms, result-100 ms] per scenario S1=529 S2=0 S3=873 S4=505 S5=602 (need >= 50 each), max pause between job runs incl. interval ends 9.91 ms (bound 100.00), producer enqueued=5496'
$cPumpS1S2 = New-FailedCheck $pumpName 'jobs run in [request+150 ms, result-100 ms] per scenario S1=25 S2=281 S3=4580 S4=505 S5=613 (need >= 50 each), max pause between job runs incl. interval ends 11.54 ms (bound 100.00), producer enqueued=9037'
$cPumpS2S4 = New-FailedCheck $pumpName 'jobs run in [request+150 ms, result-100 ms] per scenario S1=529 S2=0 S3=873 S4=3 S5=602 (need >= 50 each), max pause 9.91 ms (bound 100.00)'
$cPumpPause = New-FailedCheck $pumpName 'jobs run in [request+150 ms, result-100 ms] per scenario S1=529 S2=300 S3=873 S4=505 S5=602 (need >= 50 each), max pause between job runs incl. interval ends 180.00 ms (bound 100.00), producer enqueued=5496'
$cAppearS2 = New-FailedCheck 'S2 the real menu window appears' "class='' title='' appeared_after_ms=8030 hwnd=0"
$cStall = New-FailedCheck 'renderer: the main queue was drained during every modal (drain_calls_during > 0)' 'id1001=wakes:655/drains:0/waker_none:True id1002=wakes:832/drains:873/waker_none:False'
$cTicks = New-FailedCheck 'host: display ticks keep arriving while a modal is open (ticks_during > 0 in every modal)' 'ticks_during S1=46 S2=90 S3=0 S4=75 S5=88'
$cExc = New-FailedCheck 'run completed without exception' 'boom @ 123'
$cIdle = New-FailedCheck 'host: job latency outside any modal within budget (idle p99 <= 16.7 ms)' 'p99=40.00 ms n=455'
$cS5 = New-FailedCheck 'host: S5 one pending request at a time: a second request in the same turn is SWR_E_QUEUE_FULL, the first still delivered' 'second=SWR_E_QUEUE_FULL first_result=false'
$cS6 = New-FailedCheck 'S6 no dialog window is left after the window closed' 'dialog_gone=False'
$host1 = New-FgLine 100 1001 'S1' 'request' 'Modal06' '' $true
$host2 = New-FgLine 120 1002 'S2' 'request' 'Modal06' '' $true
$cases = @(
  @{ n = 'run-01 shape (S1 MSAA + host S1 + exit + one-off), chrome took the foreground in S1'; f = @($cMsaa, $cHostS1, $cExit, $cOneOff); l = @($host1, (New-FgLine 900 1001 'S1' 'change' 'chrome' 'Inbox - Mail')); c = 'foreground_lost'; o = 'chrome'; t = 'S1' },
  @{ n = 'same failures, the host kept the foreground'; f = @($cMsaa, $cHostS1, $cExit, $cOneOff); l = @($host1, (New-FgLine 900 1001 'S1' 'result' 'Modal06' '' $true)); c = 'real_failure' },
  @{ n = 'run-12 shape (exit + S2 pump count 0), Slack in S2'; f = @($cExit, $cPumpS2); l = @($host2, (New-FgLine 500 1002 'S2' 'change' 'Slack' 'general')); c = 'foreground_lost'; o = 'Slack'; t = 'S2' },
  @{ n = 'run-12 shape, but the foreign owner was only in S3'; f = @($cExit, $cPumpS2); l = @($host2, (New-FgLine 500 1003 'S3' 'change' 'Slack' 'general')); c = 'real_failure' },
  @{ n = 'run-14 shape (S1 + S2 failures), msedge in S1 then Teams in S2 -> earliest owner, both tags'; f = @($cMsaa, $cAppearS2, $cExit, $cHostS1, $cPumpS1S2); l = @((New-FgLine 300 1001 'S1' 'change' 'msedge' 'Docs'), (New-FgLine 2500 1002 'S2' 'change' 'Teams' 'Chat')); c = 'foreground_lost'; o = 'msedge'; t = 'S1,S2' },
  @{ n = 'run-14 shape, the foreign owner was only in S1 (S2 failure unexplained)'; f = @($cMsaa, $cAppearS2, $cExit, $cHostS1, $cPumpS1S2); l = @((New-FgLine 300 1001 'S1' 'change' 'msedge' 'Docs'), $host2); c = 'real_failure' },
  @{ n = 'a stall is never excused (foreign owner in S1 beside the stall)'; f = @($cMsaa, $cStall); l = @((New-FgLine 300 1001 'S1' 'change' 'chrome' 'x')); c = 'real_failure' },
  @{ n = 'ticks_during = 0 is never excused'; f = @($cMsaa, $cTicks); l = @((New-FgLine 300 1001 'S1' 'change' 'chrome' 'x')); c = 'real_failure' },
  @{ n = 'idle latency is never excused'; f = @($cMsaa, $cIdle); l = @((New-FgLine 300 1001 'S1' 'change' 'chrome' 'x')); c = 'real_failure' },
  @{ n = 'the one-off bound alone is not excused by a foreign owner in some modal'; f = @($cOneOff); l = @((New-FgLine 300 1002 'S2' 'change' 'chrome' 'x')); c = 'real_failure' },
  @{ n = 'an exception is never excused'; f = @($cMsaa, $cExc); l = @((New-FgLine 300 1001 'S1' 'change' 'chrome' 'x')); c = 'real_failure' },
  @{ n = 'pump check that fails on the pause bound (all counts >= 50) is real'; f = @($cMsaa, $cPumpPause); l = @((New-FgLine 300 1001 'S1' 'change' 'chrome' 'x')); c = 'real_failure' },
  @{ n = 'pump check naming S2 and S4, foreign only in S2 -> S4 unexplained'; f = @($cPumpS2S4); l = @((New-FgLine 300 1002 'S2' 'change' 'chrome' 'x')); c = 'real_failure' },
  @{ n = 'no foreground window (pid 0) is not a foreign owner'; f = @($cMsaa, $cHostS1); l = @((New-FgLine 300 1001 'S1' 'change' 'none')); c = 'real_failure' },
  @{ n = 'host window already closed (S6 teardown) is not a loss'; f = @($cS6); l = @((New-FgLine 300 1006 'S6' 'result' 'explorer' 'Program Manager' $false $false)); c = 'real_failure' },
  @{ n = 'a foreign owner outside any modal (tag -) is not a loss'; f = @($cMsaa); l = @((New-FgLine 300 0 '-' 'change' 'chrome' 'x')); c = 'real_failure' },
  @{ n = 'S5 host check, owner with spaces and a title with brackets and unicode'; f = @($cS5); l = @((New-FgLine 300 1005 'S5' 'request' 'Microsoft Edge' ('a ] b [c] ' + [char]0x65E5 + [char]0x672C))); c = 'foreground_lost'; o = 'Microsoft Edge'; t = 'S5' },
  @{ n = 'no failed checks'; f = @(); l = @((New-FgLine 300 1001 'S1' 'change' 'chrome' 'x')); c = 'pass' }
)
$caseFail = @()
foreach ($k in $cases) {
  $txt = "FGMON run=1 attempt=a1 host_pid=4000 poll_ms=10 polls=500 max_gap_ms=16 observations=$(@($k.l).Count)`r`n" + ((@($k.l) -join "`r`n") + "`r`n")
  $g = Get-FailureClass $k.f $txt
  $ok = ($g.Class -eq $k.c)
  if ($ok -and $k.o) { $ok = ($g.Owner -eq $k.o) -and (($g.Tags -join ',') -eq $k.t) }
  if (-not $ok) { $caseFail += "$($k.n): got class=$($g.Class) owner=$($g.Owner) tags=$($g.Tags -join ',') want class=$($k.c) owner=$($k.o) tags=$($k.t)" }
}
Step "foreground classification on synthetic logs ($($cases.Count) cases)" ($caseFail.Count -eq 0) $(if ($caseFail.Count -eq 0) { 'all as expected' } else { $caseFail -join ' || ' })
# the title survives the fg.log round trip (brackets, unicode, truncation at 80)
$rt = @(Read-FgLog (New-FgLine 7 1005 'S5' 'change' 'Microsoft Edge' ('x' * 100 + ']')))
Step 'fg.log round trip (owner with spaces, title truncated to 80 + ...)' ($rt.Count -eq 1 -and $rt[0].Owner -eq 'Microsoft Edge' -and $rt[0].Title.Length -eq 83 -and $rt[0].Tag -eq 'S5' -and $rt[0].Id -eq 1005 -and -not $rt[0].IsHost -and $rt[0].HostWin) "records=$($rt.Count) title_len=$(if ($rt.Count -gt 0) { $rt[0].Title.Length } else { -1 })"
# AX tally on the lines of TextGeom06 run 38 (evidence/textgeom-axfix-run38-stderr.log) and on a run killed before its memory line
$axA = Get-AxTally ("[swiftright-render] ax trailing re-throttled snapshot=9 published=8 retry_ns=1000000 n=1`r`n[swiftright-render] memory rust_live_bytes=1 ax_publishes=15 ax_throttled=8 ax_rethrottled=1`r`n")
$axB = Get-AxTally "[swiftright-render] ime_msg msg=0x0282`r`n"
Step 'AX tally parser (re-throttled line + memory counters; missing memory line)' ($axA.Seen -and $axA.Publishes -eq 15 -and $axA.Throttled -eq 8 -and $axA.Rethrottled -eq 1 -and $axA.RetryLines -eq 1 -and -not $axB.Seen -and $axB.RetryLines -eq 0) "A=$($axA.Publishes)/$($axA.Throttled)/$($axA.Rethrottled)/$($axA.RetryLines) B.seen=$($axB.Seen)"
# live: the 10 ms watch for 400 ms
[FgWatch]::Start([uint32]$PID)
Start-Sleep -Milliseconds 400
$liveSample = [FgWatch]::Sample()
[FgWatch]::Stop()
Step 'foreground watch polls at ~10 ms (>= 10 polls in 400 ms, no gap over 300 ms) and samples the foreground' ([FgWatch]::Polls -ge 10 -and [FgWatch]::MaxGapMs -le 300 -and $liveSample -ne $null) "polls=$([FgWatch]::Polls) max_gap_ms=$([FgWatch]::MaxGapMs) poll_ms=$([FgWatch]::PollMs) foreground_owner=$($liveSample.Owner) pid=$($liveSample.Pid) (none = no interactive desktop in this session)"

$left = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'SR0GM-*' })
Step 'no leftover SR0GM-* scheduled task' ($left.Count -eq 0) "found=$($left.Count)"
"dryrun $(if ($fail -eq 0) { 'PASS' } else { "FAIL ($fail)" }) ended=$(Get-Date -Format o)"
exit $(if ($fail -eq 0) { 0 } else { 1 })
