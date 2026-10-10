# Row 7 driver: runs Modal06.exe N times from INSIDE an interactive desktop session (one-shot scheduled task, see
# schedule.ps1). For every request the host logs ("MODAL id=... request ... dismiss=<instruction>") this driver finds
# the real popup menu (class #32768) or task dialog (class #32770, owned by the host window) of the host process,
# holds it open for -HoldMs (the host measures its main-queue pumping meanwhile), then dismisses it WINDOW-TARGETED:
#   menu-select:<i>:<text>  MSAA accDoDefaultAction on the menu item (falls back to PostMessage WM_KEYDOWN Down.../Return)
#   menu-escape             PostMessage WM_KEYDOWN VK_ESCAPE to the menu window (falls back to the host window)
#   menu-keys:<n>           PostMessage WM_KEYDOWN VK_DOWN x n, VK_RETURN to the menu window
#   dialog-click:<i>        PostMessage TDM_CLICK_BUTTON (WM_USER + 102) with button id 100 + i to the dialog window
#   dialog-escape           PostMessage WM_KEYDOWN VK_ESCAPE to the dialog window (falls back to WM_CLOSE)
#   dialog-observe          nothing: the host closes its window while the dialog is open (rescued if it never returns)
# No global input is ever sent.
# Modal-stall A/B (render/swiftright-render/README.md): the renderer logs one "[swiftright-render] modal id=... path=... waker_none=...
# wakes_during=... drain_calls_during=..." line per modal on stderr. This driver parses them (stderr.log of each run), asserts one line
# per modal on the expected path (posted by default, spawn with -LegacySpawn = SWR_MODAL_LEGACY_SPAWN=1) and that the main queue was
# drained during every modal (drain_calls_during > 0), and ends the result file with the stall counts and latency min/median/max.
# Foreground record (tuple 08): the Dell is in use, and TrackPopupMenu dismisses a menu whose owner loses activation. FgWatch (common.ps1) polls
# GetForegroundWindow every 10 ms for the whole run; the driver also samples it at menu request, menu shown, dismissal and result. Each attempt writes
# fg.log (owner process, class, title per observation) beside host.log. Rule, as run-matrix.sh applies it to foreground_failed: when an attempt FAILS and
# the log shows that another process held the foreground during the modal of every failing scenario, the attempt is marked
# `foreground_lost owner=<proc> title=[...]` and the run is retried ONCE as attempt a2 (a1 is kept: out\modal\run-NNa1, run-NNa2; the result file has both).
# A failure with no foreground loss in its modal is a real failure and is NOT retried; stalls (drain_calls_during = 0, ticks_during = 0), idle latency,
# exceptions and every other check are never excused. No check is weakened: a2 runs all of them, including the 50 ms open bound.
param(
  [string]$Base = 'D:\Claude\sr0-geomodal',
  [string]$Bin = '',
  [string]$OutDir = '',
  [string]$Result = '',
  [int]$Runs = 20,
  [int]$HoldMs = 1200,
  [int]$RetryDelaySec = 10,
  [switch]$LegacySpawn,
  [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $Bin) { $Bin = Join-Path $Base 'bin' }
if (-not $OutDir) { $OutDir = Join-Path $Base $(if ($LegacySpawn) { 'out\modal-legacy' } else { 'out\modal' }) }
if (-not $Result) { $Result = Join-Path $Base 'result-modal06final.txt' }

$ExpectPath = if ($LegacySpawn) { 'spawn' } else { 'posted' }
$WM_KEYDOWN = 0x0100; $WM_KEYUP = 0x0101; $WM_CLOSE = 0x0010; $TDM_CLICK_BUTTON = 0x0466
$VK_RETURN = 0x0D; $VK_ESCAPE = 0x1B; $VK_DOWN = 0x28

function Make-KeyLParam([int]$vk, [bool]$up) {
  $scan = [int64][GMWin]::MapVirtualKeyW([uint32]$vk, 0)
  $v = [int64]1 -bor ($scan -shl 16)
  if ($up) { $v = $v -bor [int64]0xC0000000L }
  return $v
}

# Posts the messages a physical key press produces to ONE window (never a global keystroke).
function Send-Key([IntPtr]$h, [int]$vk) {
  [void][GMWin]::PostMessageW($h, $script:WM_KEYDOWN, [IntPtr]$vk, [IntPtr](Make-KeyLParam $vk $false))
  Start-Sleep -Milliseconds 40
  [void][GMWin]::PostMessageW($h, $script:WM_KEYUP, [IntPtr]$vk, [IntPtr](Make-KeyLParam $vk $true))
}

function Add-Check([string]$name, [bool]$pass, [string]$detail) {
  [void]$script:checks.Add([pscustomobject]@{ name = $name; status = $(if ($pass) { 'PASS' } else { 'FAIL' }); detail = $detail })
}

# The host's popup menu (#32768) or its owned task dialog (#32770), visible, in the host process.
function Find-Modal([uint32]$ProcId, [IntPtr]$Main, [string]$Kind) {
  foreach ($h in [GMWin]::TopLevel($ProcId)) {
    if (-not [GMWin]::IsWindowVisible($h)) { continue }
    $cls = [GMWin]::ClassOf($h)
    if ($Kind -eq 'menu' -and $cls -eq '#32768') { return $h }
    if ($Kind -eq 'dialog' -and $cls -eq '#32770' -and ([GMWin]::GetWindow($h, 4) -eq $Main)) { return $h }   # GW_OWNER
  }
  return [IntPtr]::Zero
}

function Any-Dialog([uint32]$ProcId) {
  foreach ($h in [GMWin]::TopLevel($ProcId)) { if ([GMWin]::IsWindowVisible($h) -and ([GMWin]::ClassOf($h) -eq '#32770')) { return $h } }
  return [IntPtr]::Zero
}

# The Modal06 S1 menu: Open, Save (checked), separator, Delete (disabled), Quit. Every count goes through @(...): in Windows PowerShell 5.1
# a single matching object has no usable .Count (this check failed 20 of 20 in the previous run). -DryRun tests it on the items that run printed.
function Test-MenuContent($Items) {
  $a = @($Items)
  $del = @($a | Where-Object { $_.Name -like 'Delete*' } | Select-Object -First 1)
  $sav = @($a | Where-Object { $_.Name -like 'Save*' } | Select-Object -First 1)
  if ($a.Count -ne 5 -or $del.Count -ne 1 -or $sav.Count -ne 1) { return $false }
  return ((-not $del[0].Enabled) -and [bool]$sav[0].Checked -and (@($a | Where-Object { $_.Name -like 'Quit*' -and $_.Enabled }).Count -eq 1) -and (@($a | Where-Object { $_.Name -like 'Open*' -and $_.Enabled }).Count -eq 1))
}

# Renderer modal log lines (stderr): one per modal.
$script:ModalLineRe = '(?m)^\[swiftright-render\] modal id=(\d+) kind=(\w+) path=(\w+) waker_none=(\w+) queued_ms=([-\d.]+) elapsed_ms=([-\d.]+) wakes_during=(\d+) drain_calls_during=(\d+) i0=(-?\d+) i1=(-?\d+)\r?$'
function Read-ModalLines([string]$Text) {
  $out = @()
  foreach ($m in [regex]::Matches($Text, $script:ModalLineRe)) {
    $out += [pscustomobject]@{ Id = [int]$m.Groups[1].Value; Kind = $m.Groups[2].Value; Path = $m.Groups[3].Value; WakerNone = ($m.Groups[4].Value -eq 'true')
      QueuedMs = [double]$m.Groups[5].Value; ElapsedMs = [double]$m.Groups[6].Value; Wakes = [int64]$m.Groups[7].Value; Drains = [int64]$m.Groups[8].Value }
  }
  return $out
}

# The host's own view of one modal: "MODAL id=1003 result ... ticks_during=0".
function Read-TicksDuring([string]$Text) {
  $h = @{}
  foreach ($m in [regex]::Matches($Text, '(?m)^MODAL id=(\d+) result tag=\w+ .*? ticks_during=(\d+)')) { $h[[int]$m.Groups[1].Value] = [int]$m.Groups[2].Value }
  return $h
}

function Get-Median([double[]]$Xs) {
  if (-not $Xs -or $Xs.Count -eq 0) { return [double]::NaN }
  $s = @($Xs | Sort-Object); $n = $s.Count
  if ($n % 2 -eq 1) { return $s[($n - 1) / 2] }
  return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

function Fmt-Stat([string]$Name, [double[]]$Xs) {
  if (-not $Xs -or $Xs.Count -eq 0) { return "$Name n=0" }
  $mn = ($Xs | Measure-Object -Minimum).Minimum; $mx = ($Xs | Measure-Object -Maximum).Maximum
  return ('{0} n={1} min={2:N2} median={3:N2} max={4:N2}' -f $Name, $Xs.Count, $mn, (Get-Median $Xs), $mx)
}

function Wait-Gone([scriptblock]$Probe, [double]$Seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $Seconds) { if ((& $Probe) -eq [IntPtr]::Zero) { return $true }; Start-Sleep -Milliseconds 40 }
  return $false
}

# ---------------------------------------------------------------- foreground record
function Add-FgSample([string]$Tag, [int]$Id, [string]$Phase) {
  [void]$script:fgRecs.Add([pscustomobject]@{ Id = $Id; Tag = $Tag; Phase = $Phase; Rec = [FgWatch]::Sample() })
}

# Stops the watch and renders fg.log: the header, every direct sample, every change the watch saw while a modal was in progress (tag = scenario),
# and the changes outside any modal (tag '-').
function Build-FgText([int]$N, [int]$Attempt, [uint32]$HostPid) {
  [FgWatch]::Stop()
  $polls = [FgWatch]::Polls; $gap = [FgWatch]::MaxGapMs
  $rows = New-Object System.Collections.ArrayList
  foreach ($r in $script:fgRecs) { [void]$rows.Add($r) }
  foreach ($e in @([FgWatch]::All())) {
    $inSpan = $false
    foreach ($s in $script:fgSpans) { if ($e.TMs -ge $s.From -and $e.TMs -le $s.T1) { $inSpan = $true; break } }
    if (-not $inSpan) { [void]$rows.Add([pscustomobject]@{ Id = 0; Tag = '-'; Phase = 'change'; Rec = $e }) }
  }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("FGMON run=$N attempt=a$Attempt host_pid=$HostPid poll_ms=$([FgWatch]::PollMs) polls=$polls max_gap_ms=$gap observations=$($rows.Count)")
  foreach ($row in @($rows | Sort-Object { $_.Rec.TMs })) { [void]$sb.AppendLine((Format-FgRec $row.Rec $row.Id $row.Tag $row.Phase)) }
  return $sb.ToString()
}

# ---------------------------------------------------------------- one scenario (blocking; the host waits for its result)
# Wrapper: foreground owner at request and result, every change in between (from 100 ms before the request was noticed, the driver polls the host log).
function Invoke-Scenario([string]$logPath, [uint32]$ProcId, [IntPtr]$Main, [int]$id, [string]$tag, [string]$kind, [string]$dismiss) {
  $from = [FgWatch]::NowMs() - 100
  Add-FgSample $tag $id 'request'
  try { Invoke-ScenarioBody $logPath $ProcId $Main $id $tag $kind $dismiss }
  finally {
    Add-FgSample $tag $id 'result'
    $t1 = [FgWatch]::NowMs()
    foreach ($e in @([FgWatch]::Between($from, $t1))) { [void]$script:fgRecs.Add([pscustomobject]@{ Id = $id; Tag = $tag; Phase = 'change'; Rec = $e }) }
    [void]$script:fgSpans.Add([pscustomobject]@{ Id = $id; Tag = $tag; From = $from; T1 = $t1 })
  }
}

function Invoke-ScenarioBody([string]$logPath, [uint32]$ProcId, [IntPtr]$Main, [int]$id, [string]$tag, [string]$kind, [string]$dismiss) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $mw = [IntPtr]::Zero
  while ($sw.Elapsed.TotalSeconds -lt 8 -and $mw -eq [IntPtr]::Zero) {
    $mw = Find-Modal $ProcId $Main $kind
    if ($mw -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 25 }
  }
  $appearMs = [int]$sw.ElapsedMilliseconds
  $cls = if ($mw -ne [IntPtr]::Zero) { [GMWin]::ClassOf($mw) } else { '' }
  $title = if ($mw -ne [IntPtr]::Zero) { [GMWin]::TitleOf($mw) } else { '' }
  Add-FgSample $tag $id $(if ($mw -ne [IntPtr]::Zero) { 'shown' } else { 'not_shown' })
  Add-Check "$tag the real $kind window appears" ($mw -ne [IntPtr]::Zero) "class='$cls' title='$title' appeared_after_ms=$appearMs hwnd=$($mw.ToInt64())"
  if ($mw -eq [IntPtr]::Zero) { return }
  $parts = $dismiss.Split(':')
  $method = $parts[0]
  $detail = ''
  Start-Sleep -Milliseconds $HoldMs        # the host measures its main-queue pumping while the modal is open
  Add-FgSample $tag $id 'dismiss'          # the owner must still be the foreground window here, or the menu is already gone
  switch ($parts[0]) {
    'menu-select' {
      $want = $parts[2]
      # UI Automation shows a classic popup menu as one empty Pane (harness defect found in run 01, see probe-menu-uia.ps1); MSAA has the items.
      $ms = Get-MsaaItems $mw
      $items = @($ms.Items)
      $names = ($items | ForEach-Object { "$($_.Name)$(if (-not $_.Enabled) { '(disabled)' })$(if ($_.Checked) { '(checked)' })[role$($_.Role)]" }) -join ','
      $del = $items | Where-Object { $_.Name -like 'Delete*' } | Select-Object -First 1
      $sav = $items | Where-Object { $_.Name -like 'Save*' } | Select-Object -First 1
      $contentOk = Test-MenuContent $items
      Add-Check "$tag menu content visible through MSAA (Open, Save checked, separator, Delete disabled, Quit)" $contentOk "items=[$names] $($ms.Debug)"
      $target = $items | Where-Object { $_.Name -like "$want*" } | Select-Object -First 1
      $done = $false
      if ($target -ne $null) {
        try { $ms.Acc.accDoDefaultAction($target.Index); $done = $true; $method = 'msaa-accDoDefaultAction' } catch { $detail = "msaa accDoDefaultAction failed: $($_.Exception.Message); " }
      }
      if (-not $done) {
        # keyboard: Down to the n-th selectable item (the separator is skipped by the menu), then Return
        # items: Open(0) Save(1) separator(2) Delete(3) Quit(4): the separator is skipped, so Quit is 4 Down steps from the start
        $sel = [int]$parts[1]
        $downs = 0; for ($i = 0; $i -le $sel; $i++) { if ($i -ne 2) { $downs++ } }
        for ($i = 0; $i -lt $downs; $i++) { Send-Key $mw $VK_DOWN; Start-Sleep -Milliseconds 120 }
        Send-Key $mw $VK_RETURN
        $method = 'keys'
      }
    }
    'menu-escape' {
      Send-Key $mw $VK_ESCAPE
      if (-not (Wait-Gone { Find-Modal $ProcId $Main 'menu' } 2)) { Send-Key $Main $VK_ESCAPE; $method = 'escape-via-host-window' } else { $method = 'escape-to-menu-window' }
    }
    'menu-keys' {
      for ($i = 0; $i -lt [int]$parts[1]; $i++) { Send-Key $mw $VK_DOWN; Start-Sleep -Milliseconds 150 }
      Send-Key $mw $VK_RETURN
      $method = 'keys'
    }
    'dialog-click' {
      [void][GMWin]::PostMessageW($mw, $script:TDM_CLICK_BUTTON, [IntPtr](100 + [int]$parts[1]), [IntPtr]::Zero)
      $method = "TDM_CLICK_BUTTON id=$(100 + [int]$parts[1])"
    }
    'dialog-escape' {
      Send-Key $mw $VK_ESCAPE
      if (-not (Wait-Gone { Find-Modal $ProcId $Main 'dialog' } 2.5)) {
        [void][GMWin]::PostMessageW($mw, $script:WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
        $method = 'escape-ignored-WM_CLOSE-fallback'
      } else { $method = 'escape-to-dialog-window' }
    }
    'dialog-observe' { $method = 'observe' }
  }
  Add-Check "$tag modal dismissed by window-targeted input" $true "method=$method $detail"
  # the host logs the result (or, for the observe scenario, the close)
  $pat = if ($parts[0] -eq 'dialog-observe') { '^WINDOW_CLOSED' } else { "^MODAL id=$id result " }
  $limit = if ($parts[0] -eq 'dialog-observe') { 12 } else { 10 }
  $t = Wait-Log $logPath $pat $limit
  $arrived = $t -match "(?m)$pat"
  if ($parts[0] -eq 'dialog-observe') {
    $rescued = $false
    if (-not $arrived) {
      # a dialog that outlives its window: rescue it so the run can finish, and record the failure
      $dl = Any-Dialog $ProcId
      if ($dl -ne [IntPtr]::Zero) { Send-Key $dl $VK_ESCAPE; Start-Sleep -Milliseconds 800; [void][GMWin]::PostMessageW($dl, $script:WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) }
      $rescued = $true
      $t = Wait-Log $logPath $pat 10
    }
    Add-Check "$tag the window closes while its dialog is open, without a rescue" ($arrived -and -not $rescued) "window_closed_logged=$arrived rescued=$rescued"
    $gone = Wait-Gone { Any-Dialog $ProcId } 4
    Add-Check "$tag no dialog window is left after the window closed" $gone "dialog_gone=$gone"
  } else {
    Add-Check "$tag result event arrives after the dismissal" $arrived "waited up to $limit s"
  }
}

# ---------------------------------------------------------------- one run
function Invoke-ModalRun([int]$n, [int]$attempt) {
  $script:checks = New-Object System.Collections.ArrayList
  $script:fgRecs = New-Object System.Collections.ArrayList
  $script:fgSpans = New-Object System.Collections.ArrayList
  $runDir = Join-Path $OutDir ('run-{0:D2}a{1}' -f $n, $attempt)
  New-Item -ItemType Directory -Force $runDir | Out-Null
  $logPath = Join-Path $runDir 'host.log'
  $info = [ordered]@{ run = $n; attempt = $attempt; started = (Get-Date).ToString('o'); runDir = $runDir }
  $fgText = ''
  $hp = $null
  $total = [Diagnostics.Stopwatch]::StartNew()
  try {
    $envVars = @{ SWR_GM_LOG = $logPath; SWR_GM_TIMEOUT = '80' }
    if ($LegacySpawn) { $envVars['SWR_MODAL_LEGACY_SPAWN'] = '1' }
    $hp = Start-Host (Join-Path $Bin 'Modal06.exe') $Bin $envVars
    $proc = $hp.Proc
    [FgWatch]::Start([uint32]$proc.Id)
    Add-FgSample '-' 0 'start'
    $main = Wait-MainWindow $proc 30
    [FgWatch]::SetHostWindow($main.ToInt64())
    $info.hwnd = $main.ToInt64()
    if ($main -eq [IntPtr]::Zero) { throw 'no main window for Modal06' }
    $info.dpi = [GMWin]::GetDpiForWindow($main)
    $handled = @{}
    $deadline = (Get-Date).AddSeconds(90)
    while (-not $proc.HasExited -and (Get-Date) -lt $deadline) {
      $log = Read-Shared $logPath
      foreach ($m in [regex]::Matches($log, '(?m)^MODAL id=(\d+) request tag=(\w+) name=(\S+) kind=(\w+) rc=(\S+) dismiss=(\S+) ')) {
        $id = [int]$m.Groups[1].Value
        if ($handled.ContainsKey($id)) { continue }
        $handled[$id] = $true
        if ($m.Groups[5].Value -ne 'SWR_OK') { Add-Check "$($m.Groups[2].Value) request accepted" $false "rc=$($m.Groups[5].Value)"; continue }
        Invoke-Scenario $logPath ([uint32]$proc.Id) $main $id $m.Groups[2].Value $m.Groups[4].Value $m.Groups[6].Value
      }
      if ($log -match '(?m)^HOSTSUMMARY ') { break }
      Start-Sleep -Milliseconds 20
    }
    if (-not $proc.WaitForExit(40000)) { try { $proc.Kill() } catch { }; $info.killed = $true }
    $proc.WaitForExit()
    $info.exitCode = $proc.ExitCode
    $done = Read-Shared $logPath
    Add-Check 'all 6 scenarios were requested and handled' ($handled.Count -eq 6) "handled=$($handled.Count)"
    Add-Check 'host exited by itself with code 0' (($proc.ExitCode -eq 0) -and (-not $info.killed)) "exit=$($proc.ExitCode) killed=$($info.killed)"
    foreach ($hm in [regex]::Matches($done, '(?m)^HC (PASS|FAIL) (.*?) \[(.*)\]\r?$')) { Add-Check ('host: ' + $hm.Groups[2].Value) ($hm.Groups[1].Value -eq 'PASS') $hm.Groups[3].Value }
    $lat = [regex]::Match($done, '(?m)^LATENCY_MS (.*?)\r?$'); if ($lat.Success) { $info.latency = $lat.Groups[1].Value }
    # the renderer's per-modal log (stderr; the process has exited, so the pipe is complete)
    $errText = ''
    try { $errText = [string]$hp.Err.Result } catch { }
    $ml = @(Read-ModalLines $errText)
    $ticks = Read-TicksDuring $done
    $info.ax = Get-AxTally $errText
    $info.modals = @($ml | ForEach-Object { [pscustomobject]@{ id = $_.Id; kind = $_.Kind; path = $_.Path; waker_none = $_.WakerNone; queued_ms = $_.QueuedMs; elapsed_ms = $_.ElapsedMs; wakes_during = $_.Wakes; drain_calls_during = $_.Drains; ticks_during = $(if ($ticks.ContainsKey($_.Id)) { $ticks[$_.Id] } else { -1 }) } })
    $wrong = @($ml | Where-Object { $_.Path -ne $script:ExpectPath })
    Add-Check "renderer logged one modal line per modal on path=$($script:ExpectPath)" (($ml.Count -eq 6) -and ($wrong.Count -eq 0)) ("lines=$($ml.Count) (want 6) wrong_path=$($wrong.Count) paths=" + ((@($ml | ForEach-Object { $_.Path }) | Sort-Object -Unique) -join ','))
    $starved = @($ml | Where-Object { $_.Drains -le 0 })
    Add-Check 'renderer: the main queue was drained during every modal (drain_calls_during > 0)' (($ml.Count -gt 0) -and ($starved.Count -eq 0)) ((@($ml | ForEach-Object { "id$($_.Id)=wakes:$($_.Wakes)/drains:$($_.Drains)/waker_none:$($_.WakerNone)" })) -join ' ')
  } catch {
    Add-Check 'run completed without exception' $false ($_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber)
  } finally {
    $fgText = Build-FgText $n $attempt $(if ($hp -ne $null) { [uint32]$hp.Proc.Id } else { [uint32]0 })
    try { [System.IO.File]::WriteAllText((Join-Path $runDir 'fg.log'), $fgText) } catch { }
    if ($hp -ne $null) {
      $hp.Proc.Refresh()
      if (-not $hp.Proc.HasExited) { try { $hp.Proc.Kill() } catch { }; $info.killed = $true }
      try { [System.IO.File]::WriteAllText((Join-Path $runDir 'stdout.log'), [string]$hp.Out.Result) } catch { }
      try { [System.IO.File]::WriteAllText((Join-Path $runDir 'stderr.log'), [string]$hp.Err.Result) } catch { }
    }
  }
  $failed = @($script:checks | Where-Object { $_.status -ne 'PASS' })
  $class = Get-FailureClass $failed $fgText
  $info.class = $class.Class; $info.fg_owner = $class.Owner; $info.fg_title = $class.Title; $info.fg_tags = ($class.Tags -join ',')
  $info.fg_polls = [FgWatch]::Polls; $info.fg_max_gap_ms = [FgWatch]::MaxGapMs
  $info.ended = (Get-Date).ToString('o'); $info.ms = [int]$total.ElapsedMilliseconds
  $res = [ordered]@{ info = $info; overall = $(if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }); checks = $script:checks }
  [System.IO.File]::WriteAllText((Join-Path $runDir 'result.json'), ($res | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
  return [pscustomobject]@{ Run = $n; Attempt = $attempt; Pass = ($failed.Count -eq 0); Total = $script:checks.Count; Failed = $failed; Checks = @($script:checks); Info = $info; Class = $class; FgText = $fgText }
}

# The result-file lines of one attempt (also used by -DryRun on a synthetic attempt).
function Format-AttemptLines($r) {
  $out = @()
  $c = $r.Class
  $suffix = ''
  if (-not $r.Pass) {
    if ($c.Class -eq 'foreground_lost') {
      $suffix = " foreground_lost owner=$($c.Owner) title=[$($c.Title)] scenarios=$($c.Tags -join ',') first=$($c.Phase)@$($c.Wall)"
    } else {
      $suffix = " real_failure (no foreground loss explains: " + ((@($c.Unexplained) | Select-Object -First 3) -join ' | ') + ")"
    }
  }
  $out += ("RUN {0:D2} a{1} {2} checks={3}/{4} exit={5} ms={6}{7}" -f $r.Run, $r.Attempt, $(if ($r.Pass) { 'PASS' } else { 'FAIL' }), ($r.Total - @($r.Failed).Count), $r.Total, $r.Info.exitCode, $r.Info.ms, $suffix)
  if ($r.Info.latency) { $out += ("  latency_ms {0}" -f $r.Info.latency) }
  $ax = $r.Info.ax
  if ($ax -and $ax.Seen) { $out += ("  ax publishes={0} throttled={1} rethrottled={2} retry_lines={3}" -f $ax.Publishes, $ax.Throttled, $ax.Rethrottled, $ax.RetryLines) }
  elseif ($ax) { $out += ("  ax n/a (no shutdown memory line in stderr) retry_lines={0}" -f $ax.RetryLines) }
  $fl = @(Read-FgLog $r.FgText)
  $mon = [regex]::Match([string]$r.FgText, '(?m)^FGMON .*? polls=(\d+) max_gap_ms=(\d+)')
  $foreignTags = @($fl | Where-Object { Test-FgForeign $_ } | ForEach-Object { $_.Tag } | Sort-Object -Unique)
  $out += ("  fgmon polls={0} max_gap_ms={1} observations={2} foreign_in_modals={3}" -f $(if ($mon.Success) { $mon.Groups[1].Value } else { 'n/a' }), $(if ($mon.Success) { $mon.Groups[2].Value } else { 'n/a' }), $fl.Count, $(if ($foreignTags.Count -gt 0) { $foreignTags -join ',' } else { 'none' }))
  if ((-not $r.Pass) -or ($foreignTags.Count -gt 0)) { foreach ($l in @(Get-FgScenarioLines $r.FgText)) { $out += $l } }
  foreach ($m in @($r.Info.modals | Where-Object { $_ -ne $null })) {
    if ($m.drain_calls_during -le 0 -or $m.ticks_during -eq 0 -or $m.waker_none) {
      $out += ("  modal_trace id={0} kind={1} path={2} waker_none={3} wakes_during={4} drain_calls_during={5} ticks_during={6} elapsed_ms={7:N2} queued_ms={8:N2}{9}" -f $m.id, $m.kind, $m.path, $m.waker_none.ToString().ToLower(), $m.wakes_during, $m.drain_calls_during, $m.ticks_during, $m.elapsed_ms, $m.queued_ms, $(if ($m.drain_calls_during -le 0) { ' STALL' } else { '' }))
    }
  }
  foreach ($f in $r.Failed) { $d = [string]$f.detail; if ($d.Length -gt 700) { $d = $d.Substring(0, 700) + '...' }; $out += ("  FAIL {0} [{1}]" -f $f.name, $d) }
  return $out
}

# ---------------------------------------------------------------- result file and the run loop (-DryRun runs the same code on synthetic attempts)
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $lines.Add($s) }
function Save-Result { [System.IO.File]::WriteAllText($Result, [string]::Join("`r`n", $lines) + "`r`n", (New-Object System.Text.UTF8Encoding($false))) }
function Log-Stalls([string]$Label, $Set) {
  $m = @($Set | ForEach-Object { $_.Info.modals } | Where-Object { $_ -ne $null })
  $stalled = @($m | Where-Object { $_.drain_calls_during -le 0 })
  $noTicks = @($m | Where-Object { $_.ticks_during -eq 0 })
  $wn = @($m | Where-Object { $_.waker_none })
  $stalledAttempts = @($Set | Where-Object { @($_.Info.modals | Where-Object { $_.drain_calls_during -le 0 }).Count -gt 0 }).Count
  Log ("STALLS {0} attempts={1} modals={2} stalled(drain_calls_during=0)={3} ticks_during=0:{4} waker_none=true:{5} stalled_with_waker_none={6} stalled_attempts={7}" -f $Label, @($Set).Count, $m.Count, $stalled.Count, $noTicks.Count, $wn.Count, @($stalled | Where-Object { $_.waker_none }).Count, $stalledAttempts)
  foreach ($x in $stalled) { Log ("  STALL id={0} kind={1} path={2} waker_none={3} wakes_during={4} drain_calls_during={5} ticks_during={6} elapsed_ms={7:N2}" -f $x.id, $x.kind, $x.path, $x.waker_none.ToString().ToLower(), $x.wakes_during, $x.drain_calls_during, $x.ticks_during, $x.elapsed_ms) }
  if ($m.Count -gt 0) { Log ("DRAIN_CALLS_DURING_MODAL {0} min={1} (every modal needs > 0)" -f $Label, ($m | ForEach-Object { $_.drain_calls_during } | Measure-Object -Minimum).Minimum) }
}
function Log-Ax([string]$Label, $Set) {
  $seen = @($Set | Where-Object { $_.Info.ax -and $_.Info.ax.Seen })
  $sum = { param($p) $t = 0; foreach ($x in @($Set | Where-Object { $_.Info.ax })) { $t += [int]$x.Info.ax.$p }; $t }
  Log ("AX_PATH {0} attempts={1} with_counters={2} ax_publishes={3} ax_throttled={4} ax_rethrottled={5} retry_lines={6}" -f $Label, @($Set).Count, $seen.Count, (& $sum 'Publishes'), (& $sum 'Throttled'), (& $sum 'Rethrottled'), (& $sum 'RetryLines'))
  foreach ($x in @($Set | Where-Object { $_.Info.ax -and ($_.Info.ax.Rethrottled -gt 0 -or $_.Info.ax.RetryLines -gt 0) })) { Log ("  RETHROTTLED run {0:D2} a{1}: ax_rethrottled={2} retry_lines={3}" -f $x.Run, $x.Attempt, $x.Info.ax.Rethrottled, $x.Info.ax.RetryLines) }
}

# $RunOne = { param($n, $attempt) ... } returns one attempt object (Invoke-ModalRun, or a fake in -DryRun).
function Invoke-AllRuns([scriptblock]$RunOne) {
  $results = @()      # the counted attempt of each run: a2 when a1 was foreground_lost and retried, else a1
  $attempts = @()     # every attempt, a1 and a2 (both are kept)
  for ($n = 1; $n -le $Runs; $n++) {
    $r = & $RunOne $n 1
    $attempts += $r
    foreach ($l in @(Format-AttemptLines $r)) { Log $l }
    $final = $r
    if ((-not $r.Pass) -and $r.Class.Class -eq 'foreground_lost') {
      Log ("  RETRY run {0:D2} as a2 (once): a1 is foreground_lost owner={1}; waiting {2} s" -f $n, $r.Class.Owner, $RetryDelaySec)
      Save-Result
      Start-Sleep -Seconds $RetryDelaySec
      $r2 = & $RunOne $n 2
      $attempts += $r2
      foreach ($l in @(Format-AttemptLines $r2)) { Log $l }
      $final = $r2
      Log ("RUN {0:D2} FINAL {1} attempts=2 a1=foreground_lost a2={2}" -f $n, $(if ($r2.Pass) { 'PASS' } else { 'FAIL' }), $r2.Class.Class)
    }
    $results += $final
    Save-Result
    Start-Sleep -Milliseconds $script:BetweenRunsMs
  }
  $pass = @($results | Where-Object { $_.Pass }).Count
  $firstPass = @($attempts | Where-Object { $_.Attempt -eq 1 -and $_.Pass }).Count
  $retried = @($attempts | Where-Object { $_.Attempt -eq 2 })
  $retriedPass = @($retried | Where-Object { $_.Pass }).Count
  $fgLost = @($attempts | Where-Object { (-not $_.Pass) -and $_.Class.Class -eq 'foreground_lost' })
  $realFail = @($attempts | Where-Object { (-not $_.Pass) -and $_.Class.Class -eq 'real_failure' })
  Log ''
  Log "--- run 01 checks (what is asserted) ---"
  if ($results.Count -gt 0) { foreach ($c in $results[0].Checks) { $d = [string]$c.detail; if ($d.Length -gt 300) { $d = $d.Substring(0, 300) + '...' }; Log ("{0} {1} [{2}]" -f $c.status, $c.name, $d) } }
  Log ''
  Log ("SUMMARY runs={0} pass={1} fail={2} checks_per_run={3}" -f $Runs, $pass, ($Runs - $pass), $(if ($results.Count -gt 0) { $results[0].Total } else { 0 }))
  Log ("ATTEMPTS total={0} first_attempt_pass={1}/{2} foreground_lost_attempts={3} retried_a2={4} retried_a2_pass={5} real_failure_attempts={6}" -f $attempts.Count, $firstPass, $Runs, $fgLost.Count, $retried.Count, $retriedPass, $realFail.Count)
  foreach ($x in $fgLost) {
    $fin = @($results | Where-Object { $_.Run -eq $x.Run })[0]
    Log ("FOREGROUND_LOST run {0:D2} a{1} owner={2} title=[{3}] scenarios={4} first={5}@{6} -> run final {7}" -f $x.Run, $x.Attempt, $x.Class.Owner, $x.Class.Title, ($x.Class.Tags -join ','), $x.Class.Phase, $x.Class.Wall, $(if ($fin.Pass) { 'PASS' } else { 'FAIL' }))
  }
  foreach ($x in $realFail) { Log ("REAL_FAILURE run {0:D2} a{1}: {2}" -f $x.Run, $x.Attempt, ((@($x.Class.Unexplained) | Select-Object -First 4) -join ' | ')) }
  $all = @($results | ForEach-Object { $_.Info.modals } | Where-Object { $_ -ne $null })
  Log ("MODAL_PATH expected={0} lines={1} counted attempts (runs x 6 = {2}) paths_seen={3}" -f $ExpectPath, $all.Count, ($Runs * 6), ((@($all | ForEach-Object { $_.path }) | Sort-Object -Unique) -join ','))
  Log-Stalls 'counted_attempts' $results
  Log-Stalls 'all_attempts' $attempts
  Log-Ax 'counted_attempts' $results
  Log-Ax 'all_attempts' $attempts
  # latency across runs: per attempt, the host's LATENCY_MS line (ms)
  $getv = { param($pat, $set) @($set | ForEach-Object { $m = [regex]::Match([string]$_.Info.latency, $pat); if ($m.Success) { [double]$m.Groups[1].Value } }) }
  Log ('LATENCY_ACROSS_RUNS (ms, per-run values of the counted attempts)')
  Log ('  ' + (Fmt-Stat 'modal_open_one_off max' (& $getv 'modal_open_one_off n=\d+ max=([-\d.]+)' $results)))
  Log ('  ' + (Fmt-Stat 'modal_steady p99' (& $getv 'modal_steady n=\d+ p50=[-\d.]+ p99=([-\d.]+)' $results)))
  Log ('  ' + (Fmt-Stat 'modal_steady max' (& $getv 'modal_steady n=\d+ p50=[-\d.]+ p99=[-\d.]+ max=([-\d.]+)' $results)))
  Log ('  ' + (Fmt-Stat 'all-jobs max' (& $getv '^all n=\d+ p50=[-\d.]+ p99=[-\d.]+ max=([-\d.]+)' $results)))
  Log ('  ' + (Fmt-Stat 'modal elapsed (renderer)' (@($all | ForEach-Object { [double]$_.elapsed_ms }))))
  Log ('  ' + (Fmt-Stat 'modal_open_one_off max, ALL attempts (50 ms bound; a foreground_lost a1 is included here)' (& $getv 'modal_open_one_off n=\d+ max=([-\d.]+)' $attempts)))
  Log "ROW7 MODAL $(if ($pass -eq $Runs) { 'PASS' } else { 'FAIL' }) ($pass/$Runs runs: $firstPass on a1, $retriedPass on a2 after foreground_lost; real failures $($realFail.Count))"
  Log "ended=$(Get-Date -Format o)"
  Save-Result
}
$script:BetweenRunsMs = 1500

# ---------------------------------------------------------------- dry run: nothing here touches the desktop
if ($DryRun) {
  $fails = @()
  if ((Make-KeyLParam $VK_ESCAPE $false) -ne 0x00010001) { $fails += "keydown lparam $(Make-KeyLParam $VK_ESCAPE $false)" }
  if ((Make-KeyLParam $VK_ESCAPE $true) -ne ([int64]0xC0010001L)) { $fails += "keyup lparam $(Make-KeyLParam $VK_ESCAPE $true)" }
  if ($TDM_CLICK_BUTTON -ne (0x400 + 102)) { $fails += 'TDM_CLICK_BUTTON' }
  # the dialog/menu finders run against a process that owns neither (this one): they must return nothing
  if ((Find-Modal ([uint32]$PID) ([IntPtr]::Zero) 'menu') -ne [IntPtr]::Zero) { $fails += 'Find-Modal(menu) found something in the driver process' }
  if ((Find-Modal ([uint32]$PID) ([IntPtr]::Zero) 'dialog') -ne [IntPtr]::Zero) { $fails += 'Find-Modal(dialog) found something in the driver process' }
  $dm = [regex]::Match('MODAL id=1001 request tag=S1 name=menu-select kind=menu rc=SWR_OK dismiss=menu-select:4:Quit title= at_ms=1.00', '(?m)^MODAL id=(\d+) request tag=(\w+) name=(\S+) kind=(\w+) rc=(\S+) dismiss=(\S+) ')
  if (-not $dm.Success -or $dm.Groups[6].Value -ne 'menu-select:4:Quit') { $fails += 'request line regex' }
  # menu content check, on the exact items the first Modal06 run printed (they were rejected by the pre-fix check)
  $mk = { param($n, $st) [pscustomobject]@{ Index = 1; Name = $n; State = $st; Role = 12; Enabled = (($st -band 1) -eq 0); Checked = (($st -band 0x10) -ne 0) } }
  $good = @((& $mk 'Open' 0), (& $mk 'Save' 0x10), (& $mk '' 1), (& $mk 'Delete' 1), (& $mk 'Quit' 0))
  if (-not (Test-MenuContent $good)) { $fails += 'Test-MenuContent rejects the observed good menu' }
  if (Test-MenuContent @($good[0..3])) { $fails += 'Test-MenuContent accepts a menu with 4 items' }
  if (Test-MenuContent @((& $mk 'Open' 0), (& $mk 'Save' 0), (& $mk '' 1), (& $mk 'Delete' 1), (& $mk 'Quit' 0))) { $fails += 'Test-MenuContent accepts an unchecked Save' }
  if (Test-MenuContent (& $mk 'Open' 0)) { $fails += 'Test-MenuContent accepts a single object' }
  # renderer modal-line parser and the stall classification
  $okLine = '[swiftright-render] modal id=1003 kind=dialog path=spawn waker_none=true queued_ms=1.25 elapsed_ms=1252.93 wakes_during=611 drain_calls_during=0 i0=22 i1=1'
  $okLine2 = '[swiftright-render] modal id=1001 kind=menu path=posted waker_none=false queued_ms=0.40 elapsed_ms=1272.19 wakes_during=640 drain_calls_during=1500 i0=15 i1=4'
  $pl = @(Read-ModalLines ($okLine + "`r`n" + $okLine2 + "`r`n"))
  if ($pl.Count -ne 2) { $fails += "Read-ModalLines count $($pl.Count)" }
  elseif (-not ($pl[0].Id -eq 1003 -and $pl[0].Path -eq 'spawn' -and $pl[0].WakerNone -and $pl[0].Drains -eq 0 -and $pl[0].Wakes -eq 611 -and $pl[1].Drains -eq 1500 -and -not $pl[1].WakerNone)) { $fails += 'Read-ModalLines fields' }
  $tk = Read-TicksDuring "MODAL id=1003 result tag=S3 action=3 i0=22 i1=1 choice=22/1 failed=false elapsed_ms=1252.93 ticks_during=0 at_ms=6025.36`r`n"
  if ($tk[1003] -ne 0) { $fails += 'Read-TicksDuring' }
  if ((Get-Median @(3.0, 1.0, 2.0)) -ne 2 -or (Get-Median @(4.0, 1.0, 2.0, 3.0)) -ne 2.5) { $fails += 'Get-Median' }
  # foreground record through the real Invoke-Scenario wrapper (stub body: no host, no window, no input) and the live 10 ms watch (it only polls GetForegroundWindow)
  function Invoke-ScenarioBody { param($logPath, $ProcId, $Main, $id, $tag, $kind, $dismiss) Add-FgSample $tag $id 'shown'; Start-Sleep -Milliseconds 400 }
  $script:fgRecs = New-Object System.Collections.ArrayList; $script:fgSpans = New-Object System.Collections.ArrayList
  [FgWatch]::Start([uint32]$PID)
  Add-FgSample '-' 0 'start'
  Invoke-Scenario 'stub.log' ([uint32]$PID) ([IntPtr]::Zero) 1001 'S1' 'menu' 'menu-escape'
  $spanCount = @($script:fgSpans).Count
  $fgLive = Build-FgText 1 1 ([uint32]$PID)
  $fgl = @(Read-FgLog $fgLive)
  $fgm = [regex]::Match($fgLive, '(?m)^FGMON run=1 attempt=a1 host_pid=(\d+) poll_ms=10 polls=(\d+) max_gap_ms=(\d+) ')
  if (-not $fgm.Success) { $fails += 'FGMON header missing' }
  elseif ([int]$fgm.Groups[2].Value -lt 10 -or [int]$fgm.Groups[3].Value -gt 300) { $fails += "foreground watch polls=$($fgm.Groups[2].Value) max_gap_ms=$($fgm.Groups[3].Value) in 400 ms (want >= 10 polls, no gap over 300 ms)" }
  foreach ($ph in 'request', 'shown', 'result') { if (@($fgl | Where-Object { $_.Phase -eq $ph -and $_.Tag -eq 'S1' -and $_.Id -eq 1001 }).Count -ne 1) { $fails += "Invoke-Scenario wrapper: fg.log lacks exactly one S1 $ph sample" } }
  if ($spanCount -ne 1) { $fails += "Invoke-Scenario wrapper: spans=$spanCount (want 1)" }
  # Invoke-ModalRun plumbing with a stub host that exits at once: no window appears, so the run ends in the exception path; fg.log, result.json and the class must still be written
  function Start-Host([string]$Exe, [string]$Bin, [hashtable]$EnvVars) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$env:SystemRoot\System32\cmd.exe"; $psi.Arguments = '/c exit 0'; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    return [pscustomobject]@{ Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
  }
  $OutDir = Join-Path $env:TEMP 'sr0gm-dryrun-out'
  $rr = Invoke-ModalRun 1 1
  if ($rr.Pass -or $rr.Class.Class -ne 'real_failure' -or (@($rr.Failed | Where-Object { $_.name -eq 'run completed without exception' }).Count -ne 1)) { $fails += "Invoke-ModalRun stub run: pass=$($rr.Pass) class=$($rr.Class.Class)" }
  foreach ($fn in 'fg.log', 'result.json') { if (-not (Test-Path (Join-Path $OutDir "run-01a1\$fn"))) { $fails += "Invoke-ModalRun stub run did not write $fn" } }
  $rj = $null; try { $rj = Get-Content -Raw (Join-Path $OutDir 'run-01a1\result.json') | ConvertFrom-Json } catch { }
  if ($rj -eq $null -or $rj.info.class -ne 'real_failure' -or $rj.info.attempt -ne 1) { $fails += 'Invoke-ModalRun stub run: result.json lacks info.class / info.attempt' }
  if (@(Format-AttemptLines $rr).Count -lt 2) { $fails += 'Format-AttemptLines on the stub run' }
  $synthFg = (Format-FgRec ([pscustomobject]@{ TMs = 100; Wall = '10:00:00.100'; Hwnd = 7; Pid = 4000; Owner = 'Modal06'; Class = 'X'; Title = ''; IsHost = $true; HostWinAlive = $true }) 1001 'S1' 'request') + "`r`n" +
    (Format-FgRec ([pscustomobject]@{ TMs = 900; Wall = '10:00:00.900'; Hwnd = 9; Pid = 5000; Owner = 'chrome'; Class = 'Chrome_WidgetWin_1'; Title = 'Inbox [3] - Mail'; IsHost = $false; HostWinAlive = $true }) 1001 'S1' 'change') + "`r`n"
  $synthFail = @([pscustomobject]@{ name = 'S1 menu content visible through MSAA (Open, Save checked, separator, Delete disabled, Quit)'; status = 'FAIL'; detail = 'items=[] hr=0x80004005 ptr=0' },
                 [pscustomobject]@{ name = 'host exited by itself with code 0'; status = 'FAIL'; detail = 'exit=1 killed=' })
  $synth = [pscustomobject]@{ Run = 3; Attempt = 1; Pass = $false; Total = 44; Failed = $synthFail; FgText = $synthFg; Class = (Get-FailureClass $synthFail $synthFg)
    Info = [ordered]@{ exitCode = 1; ms = 1234; latency = ''; ax = (Get-AxTally "[swiftright-render] memory x ax_publishes=1 ax_throttled=0 ax_rethrottled=0`r`n"); modals = @() } }
  $sl = (Format-AttemptLines $synth) -join "`n"
  if ($sl -notmatch 'RUN 03 a1 FAIL checks=42/44 exit=1 ms=1234 foreground_lost owner=chrome title=\[Inbox \[3\] - Mail\] scenarios=S1 ') { $fails += "Format-AttemptLines: $sl" }
  if ($sl -notmatch 'ax publishes=1 throttled=0 rethrottled=0 retry_lines=0') { $fails += 'Format-AttemptLines: ax line' }
  if ($sl -notmatch 'fg S1 request=Modal06 shown=- dismiss=- result=- changes=1 FOREIGN=chrome') { $fails += 'Format-AttemptLines: fg scenario line' }
  # the run loop on synthetic attempts: run 1 passes on a1; run 2 a1 foreground_lost -> a2 passes; run 3 a1 real failure (no retry); run 4 a1 and a2 foreground_lost (one retry only)
  $tmpResult = Join-Path $env:TEMP 'modal-dryrun-result.txt'
  $Result = $tmpResult; $Runs = 4; $RetryDelaySec = 0; $script:BetweenRunsMs = 0
  $lines.Clear()
  $fgOK = (Format-FgRec ([pscustomobject]@{ TMs = 10; Wall = '10:00:00.010'; Hwnd = 7; Pid = 4000; Owner = 'Modal06'; Class = 'X'; Title = ''; IsHost = $true; HostWinAlive = $true }) 1001 'S1' 'request') + "`r`n"
  $fgLostLog = $fgOK + (Format-FgRec ([pscustomobject]@{ TMs = 20; Wall = '10:00:00.020'; Hwnd = 9; Pid = 5000; Owner = 'chrome'; Class = 'C'; Title = 'tab'; IsHost = $false; HostWinAlive = $true }) 1001 'S1' 'change') + "`r`n"
  $nm = New-Object System.Collections.ArrayList
  $mkAttempt = {
    param($n, $a, $failedChecks, $fgText, $mods, $ax, $lat)
    $cls = Get-FailureClass $failedChecks $fgText
    [pscustomobject]@{ Run = $n; Attempt = $a; Pass = (@($failedChecks).Count -eq 0); Total = 44; Failed = @($failedChecks); Checks = @(); FgText = $fgText; Class = $cls
      Info = [ordered]@{ exitCode = $(if (@($failedChecks).Count -eq 0) { 0 } else { 1 }); ms = 12000; latency = $lat; ax = $ax; modals = @($mods) } }
  }
  $goodMods = @(1..6 | ForEach-Object { [pscustomobject]@{ id = 1000 + $_; kind = 'menu'; path = 'posted'; waker_none = $false; queued_ms = 0.1; elapsed_ms = 1270.0; wakes_during = 600; drain_calls_during = 700; ticks_during = 70 } })
  $stallMods = @(1..6 | ForEach-Object { [pscustomobject]@{ id = 1000 + $_; kind = 'dialog'; path = 'posted'; waker_none = ($_ -eq 3); queued_ms = 0.1; elapsed_ms = 1270.0; wakes_during = 600; drain_calls_during = $(if ($_ -eq 3) { 0 } else { 700 }); ticks_during = 70 } })
  $axOk = Get-AxTally "[swiftright-render] memory x ax_publishes=1 ax_throttled=0 ax_rethrottled=0`r`n"
  $axRt = Get-AxTally "[swiftright-render] ax trailing re-throttled snapshot=9 published=8 retry_ns=1000000 n=1`r`n[swiftright-render] memory x ax_publishes=15 ax_throttled=8 ax_rethrottled=1`r`n"
  $lat1 = 'all n=5700 p50=0.06 p99=7.00 max=39.00 | modal_open_one_off n=375 max=30.00 | modal_steady n=2900 p50=0.06 p99=0.40 max=8.00 max_run_gap=10.00 | idle n=455 p99=0.30 max=0.50'
  $lat2 = 'all n=5700 p50=0.06 p99=7.00 max=52.19 | modal_open_one_off n=375 max=52.19 | modal_steady n=2900 p50=0.06 p99=0.40 max=8.00 max_run_gap=10.00 | idle n=455 p99=0.30 max=0.50'
  $fakeFail = @(
    [pscustomobject]@{ name = 'S1 menu content visible through MSAA (Open, Save checked, separator, Delete disabled, Quit)'; status = 'FAIL'; detail = 'items=[] hr=0x80004005 ptr=0' },
    [pscustomobject]@{ name = 'host exited by itself with code 0'; status = 'FAIL'; detail = 'exit=1 killed=' })
  $fakeStall = @([pscustomobject]@{ name = 'renderer: the main queue was drained during every modal (drain_calls_during > 0)'; status = 'FAIL'; detail = 'id1003=wakes:655/drains:0/waker_none:True' })
  $fakeRun = {
    param($n, $a)
    switch ("$n.$a") {
      '1.1' { & $mkAttempt $n $a @() $fgOK $goodMods $axOk $lat1 }
      '2.1' { & $mkAttempt $n $a $fakeFail $fgLostLog $goodMods $axOk $lat2 }
      '2.2' { & $mkAttempt $n $a @() $fgOK $goodMods $axRt $lat1 }
      '3.1' { & $mkAttempt $n $a $fakeStall $fgLostLog $stallMods $axOk $lat1 }
      '4.1' { & $mkAttempt $n $a $fakeFail $fgLostLog $goodMods $axOk $lat1 }
      '4.2' { & $mkAttempt $n $a $fakeFail $fgLostLog $goodMods $axOk $lat1 }
    }
  }
  Invoke-AllRuns $fakeRun
  $rt = Get-Content -Raw $tmpResult
  foreach ($want in @('^RUN 01 a1 PASS checks=44/44', '^RUN 02 a1 FAIL checks=42/44 .* foreground_lost owner=chrome title=\[tab\] scenarios=S1 ', '^  RETRY run 02 as a2 \(once\)', '^RUN 02 a2 PASS', '^RUN 02 FINAL PASS attempts=2 a1=foreground_lost a2=pass',
      '^RUN 03 a1 FAIL .* real_failure \(no foreground loss explains: renderer: the main queue was drained', '^  modal_trace id=1003 .* STALL', '^RUN 04 FINAL FAIL attempts=2 a1=foreground_lost a2=foreground_lost',
      '^SUMMARY runs=4 pass=2 fail=2 checks_per_run=44', '^ATTEMPTS total=6 first_attempt_pass=1/4 foreground_lost_attempts=3 retried_a2=2 retried_a2_pass=1 real_failure_attempts=1',
      '^FOREGROUND_LOST run 02 a1 owner=chrome .* -> run final PASS', '^FOREGROUND_LOST run 04 a2 owner=chrome .* -> run final FAIL', '^REAL_FAILURE run 03 a1: renderer: the main queue',
      '^STALLS counted_attempts attempts=4 modals=24 stalled\(drain_calls_during=0\)=1 ', '^STALLS all_attempts attempts=6 modals=36 stalled\(drain_calls_during=0\)=1 ',
      '^AX_PATH counted_attempts attempts=4 with_counters=4 ax_publishes=18 ax_throttled=8 ax_rethrottled=1 retry_lines=1', '^AX_PATH all_attempts attempts=6 .* ax_rethrottled=1 retry_lines=1', '^  RETHROTTLED run 02 a2: ax_rethrottled=1 retry_lines=1',
      'modal_open_one_off max, ALL attempts .* n=6 min=30\.00 median=30\.00 max=52\.19', '^ROW7 MODAL FAIL \(2/4 runs: 1 on a1, 1 on a2 after foreground_lost; real failures 1\)')) {
    if ($rt -notmatch "(?m)$want") { $fails += "run loop result lacks /$want/" }
  }
  if ($env:SR0GM_DRYRUN_SHOW) { Write-Output $rt }      # SR0GM_DRYRUN_SHOW=1: print the synthetic result file
  $parse = Test-ParseFile $PSCommandPath
  if ($parse.Count -ne 0) { $fails += "parse errors: $($parse.Count)" }
  foreach ($f in $fails) { Write-Output "DRYRUN FAIL $f" }
  Write-Output ("DRYRUN drive-modal logic " + $(if ($fails.Count -eq 0) { 'PASS' } else { 'FAIL' }))
  exit $(if ($fails.Count -eq 0) { 0 } else { 1 })
}

# ---------------------------------------------------------------- the N runs
New-Item -ItemType Directory -Force $OutDir | Out-Null
Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o) runs=$Runs hold_ms=$HoldMs fg_poll_ms=$([FgWatch]::PollMs) retry_delay_s=$RetryDelaySec attempts=a1, then one a2 only after foreground_lost"
Log (Get-Artifacts $Bin @('Modal06.exe'))
Invoke-AllRuns { param($n, $attempt) Invoke-ModalRun $n $attempt }
