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
param(
  [string]$Base = 'D:\Claude\sr0-geomodal',
  [string]$Bin = '',
  [string]$OutDir = '',
  [string]$Result = '',
  [int]$Runs = 20,
  [int]$HoldMs = 1200,
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

# ---------------------------------------------------------------- one scenario (blocking; the host waits for its result)
function Invoke-Scenario([string]$logPath, [uint32]$ProcId, [IntPtr]$Main, [int]$id, [string]$tag, [string]$kind, [string]$dismiss) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $mw = [IntPtr]::Zero
  while ($sw.Elapsed.TotalSeconds -lt 8 -and $mw -eq [IntPtr]::Zero) {
    $mw = Find-Modal $ProcId $Main $kind
    if ($mw -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 25 }
  }
  $appearMs = [int]$sw.ElapsedMilliseconds
  $cls = if ($mw -ne [IntPtr]::Zero) { [GMWin]::ClassOf($mw) } else { '' }
  $title = if ($mw -ne [IntPtr]::Zero) { [GMWin]::TitleOf($mw) } else { '' }
  Add-Check "$tag the real $kind window appears" ($mw -ne [IntPtr]::Zero) "class='$cls' title='$title' appeared_after_ms=$appearMs hwnd=$($mw.ToInt64())"
  if ($mw -eq [IntPtr]::Zero) { return }
  $parts = $dismiss.Split(':')
  $method = $parts[0]
  $detail = ''
  Start-Sleep -Milliseconds $HoldMs        # the host measures its main-queue pumping while the modal is open
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
function Invoke-ModalRun([int]$n) {
  $script:checks = New-Object System.Collections.ArrayList
  $runDir = Join-Path $OutDir ('run-{0:D2}' -f $n)
  New-Item -ItemType Directory -Force $runDir | Out-Null
  $logPath = Join-Path $runDir 'host.log'
  $info = [ordered]@{ run = $n; started = (Get-Date).ToString('o'); runDir = $runDir }
  $hp = $null
  $total = [Diagnostics.Stopwatch]::StartNew()
  try {
    $envVars = @{ SWR_GM_LOG = $logPath; SWR_GM_TIMEOUT = '80' }
    if ($LegacySpawn) { $envVars['SWR_MODAL_LEGACY_SPAWN'] = '1' }
    $hp = Start-Host (Join-Path $Bin 'Modal06.exe') $Bin $envVars
    $proc = $hp.Proc
    $main = Wait-MainWindow $proc 30
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
      Start-Sleep -Milliseconds 60
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
    $info.modals = @($ml | ForEach-Object { [pscustomobject]@{ id = $_.Id; kind = $_.Kind; path = $_.Path; waker_none = $_.WakerNone; queued_ms = $_.QueuedMs; elapsed_ms = $_.ElapsedMs; wakes_during = $_.Wakes; drain_calls_during = $_.Drains; ticks_during = $(if ($ticks.ContainsKey($_.Id)) { $ticks[$_.Id] } else { -1 }) } })
    $wrong = @($ml | Where-Object { $_.Path -ne $script:ExpectPath })
    Add-Check "renderer logged one modal line per modal on path=$($script:ExpectPath)" (($ml.Count -eq 6) -and ($wrong.Count -eq 0)) ("lines=$($ml.Count) (want 6) wrong_path=$($wrong.Count) paths=" + ((@($ml | ForEach-Object { $_.Path }) | Sort-Object -Unique) -join ','))
    $starved = @($ml | Where-Object { $_.Drains -le 0 })
    Add-Check 'renderer: the main queue was drained during every modal (drain_calls_during > 0)' (($ml.Count -gt 0) -and ($starved.Count -eq 0)) ((@($ml | ForEach-Object { "id$($_.Id)=wakes:$($_.Wakes)/drains:$($_.Drains)/waker_none:$($_.WakerNone)" })) -join ' ')
  } catch {
    Add-Check 'run completed without exception' $false ($_.Exception.Message + ' @ ' + $_.InvocationInfo.ScriptLineNumber)
  } finally {
    if ($hp -ne $null) {
      $hp.Proc.Refresh()
      if (-not $hp.Proc.HasExited) { try { $hp.Proc.Kill() } catch { }; $info.killed = $true }
      try { [System.IO.File]::WriteAllText((Join-Path $runDir 'stdout.log'), [string]$hp.Out.Result) } catch { }
      try { [System.IO.File]::WriteAllText((Join-Path $runDir 'stderr.log'), [string]$hp.Err.Result) } catch { }
    }
  }
  $failed = @($script:checks | Where-Object { $_.status -ne 'PASS' })
  $info.ended = (Get-Date).ToString('o'); $info.ms = [int]$total.ElapsedMilliseconds
  $res = [ordered]@{ info = $info; overall = $(if ($failed.Count -eq 0) { 'PASS' } else { 'FAIL' }); checks = $script:checks }
  [System.IO.File]::WriteAllText((Join-Path $runDir 'result.json'), ($res | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
  return [pscustomobject]@{ Run = $n; Pass = ($failed.Count -eq 0); Total = $script:checks.Count; Failed = $failed; Checks = @($script:checks); Info = $info }
}

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
  $parse = Test-ParseFile $PSCommandPath
  if ($parse.Count -ne 0) { $fails += "parse errors: $($parse.Count)" }
  foreach ($f in $fails) { Write-Output "DRYRUN FAIL $f" }
  Write-Output ("DRYRUN drive-modal logic " + $(if ($fails.Count -eq 0) { 'PASS' } else { 'FAIL' }))
  exit $(if ($fails.Count -eq 0) { 0 } else { 1 })
}

# ---------------------------------------------------------------- the N runs
New-Item -ItemType Directory -Force $OutDir | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $lines.Add($s) }
Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o) runs=$Runs hold_ms=$HoldMs"
Log (Get-Artifacts $Bin @('Modal06.exe'))
$results = @()
for ($n = 1; $n -le $Runs; $n++) {
  $r = Invoke-ModalRun $n
  $results += $r
  Log ("RUN {0:D2} {1} checks={2}/{3} exit={4} ms={5}" -f $n, $(if ($r.Pass) { 'PASS' } else { 'FAIL' }), ($r.Total - $r.Failed.Count), $r.Total, $r.Info.exitCode, $r.Info.ms)
  if ($r.Info.latency) { Log ("  latency_ms {0}" -f $r.Info.latency) }
  foreach ($m in @($r.Info.modals | Where-Object { $_ -ne $null })) {
    if ($m.drain_calls_during -le 0 -or $m.ticks_during -eq 0 -or $m.waker_none) {
      Log ("  modal_trace id={0} kind={1} path={2} waker_none={3} wakes_during={4} drain_calls_during={5} ticks_during={6} elapsed_ms={7:N2} queued_ms={8:N2}{9}" -f $m.id, $m.kind, $m.path, $m.waker_none.ToString().ToLower(), $m.wakes_during, $m.drain_calls_during, $m.ticks_during, $m.elapsed_ms, $m.queued_ms, $(if ($m.drain_calls_during -le 0) { ' STALL' } else { '' }))
    }
  }
  foreach ($f in $r.Failed) { $d = [string]$f.detail; if ($d.Length -gt 700) { $d = $d.Substring(0, 700) + '...' }; Log ("  FAIL {0} [{1}]" -f $f.name, $d) }
  [System.IO.File]::WriteAllText($Result, [string]::Join("`r`n", $lines) + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
  Start-Sleep -Milliseconds 1500
}
$pass = @($results | Where-Object { $_.Pass }).Count
Log ''
Log "--- run 01 checks (what is asserted) ---"
if ($results.Count -gt 0) { foreach ($c in $results[0].Checks) { $d = [string]$c.detail; if ($d.Length -gt 300) { $d = $d.Substring(0, 300) + '...' }; Log ("{0} {1} [{2}]" -f $c.status, $c.name, $d) } }
Log ''
Log ("SUMMARY runs={0} pass={1} fail={2} checks_per_run={3}" -f $Runs, $pass, ($Runs - $pass), $(if ($results.Count -gt 0) { $results[0].Total } else { 0 }))
$all = @($results | ForEach-Object { $_.Info.modals } | Where-Object { $_ -ne $null })
$stalled = @($all | Where-Object { $_.drain_calls_during -le 0 })
$noTicks = @($all | Where-Object { $_.ticks_during -eq 0 })
$wn = @($all | Where-Object { $_.waker_none })
Log ("MODAL_PATH expected={0} lines={1} (runs x 6 = {2}) paths_seen={3}" -f $ExpectPath, $all.Count, ($Runs * 6), ((@($all | ForEach-Object { $_.path }) | Sort-Object -Unique) -join ','))
Log ("STALLS modals={0} stalled(drain_calls_during=0)={1} ticks_during=0:{2} waker_none=true:{3} stalled_with_waker_none={4} stalled_runs={5}" -f $all.Count, $stalled.Count, $noTicks.Count, $wn.Count, @($stalled | Where-Object { $_.waker_none }).Count, @($results | Where-Object { @($_.Info.modals | Where-Object { $_.drain_calls_during -le 0 }).Count -gt 0 } | ForEach-Object { $_.Run }).Count)
foreach ($m in $stalled) { Log ("  STALL id={0} kind={1} path={2} waker_none={3} wakes_during={4} drain_calls_during={5} ticks_during={6} elapsed_ms={7:N2}" -f $m.id, $m.kind, $m.path, $m.waker_none.ToString().ToLower(), $m.wakes_during, $m.drain_calls_during, $m.ticks_during, $m.elapsed_ms) }
if ($all.Count -gt 0) {
  $minDrain = ($all | ForEach-Object { $_.drain_calls_during } | Measure-Object -Minimum).Minimum
  Log ("DRAIN_CALLS_DURING_MODAL min={0} (every modal needs > 0)" -f $minDrain)
}
# latency across runs: per run, the host's LATENCY_MS line (ms)
$getv = { param($pat) @($results | ForEach-Object { $m = [regex]::Match([string]$_.Info.latency, $pat); if ($m.Success) { [double]$m.Groups[1].Value } }) }
Log ('LATENCY_ACROSS_RUNS (ms, per-run values)')
Log ('  ' + (Fmt-Stat 'modal_open_one_off max' (& $getv 'modal_open_one_off n=\d+ max=([-\d.]+)')))
Log ('  ' + (Fmt-Stat 'modal_steady p99' (& $getv 'modal_steady n=\d+ p50=[-\d.]+ p99=([-\d.]+)')))
Log ('  ' + (Fmt-Stat 'modal_steady max' (& $getv 'modal_steady n=\d+ p50=[-\d.]+ p99=[-\d.]+ max=([-\d.]+)')))
Log ('  ' + (Fmt-Stat 'all-jobs max' (& $getv '^all n=\d+ p50=[-\d.]+ p99=[-\d.]+ max=([-\d.]+)')))
Log ('  ' + (Fmt-Stat 'modal elapsed (renderer)' (@($all | ForEach-Object { [double]$_.elapsed_ms }))))
Log "ROW7 MODAL $(if ($pass -eq $Runs) { 'PASS' } else { 'FAIL' }) ($pass/$Runs runs)"
Log "ended=$(Get-Date -Format o)"
[System.IO.File]::WriteAllText($Result, [string]::Join("`r`n", $lines) + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
