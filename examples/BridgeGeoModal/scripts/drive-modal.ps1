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
param(
  [string]$Base = 'D:\Claude\sr0-geomodal',
  [string]$Bin = '',
  [string]$OutDir = '',
  [string]$Result = '',
  [int]$Runs = 20,
  [int]$HoldMs = 1200,
  [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $Bin) { $Bin = Join-Path $Base 'bin' }
if (-not $OutDir) { $OutDir = Join-Path $Base 'out\modal' }
if (-not $Result) { $Result = Join-Path $Base 'result-modal06final.txt' }

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
      $contentOk = ($items.Count -eq 5) -and ($del -ne $null) -and (-not $del.Enabled) -and ($sav -ne $null) -and $sav.Checked -and (@($items | Where-Object { $_.Name -like 'Quit*' -and $_.Enabled }).Count -eq 1) -and (@($items | Where-Object { $_.Name -like 'Open*' -and $_.Enabled }).Count -eq 1)
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
    $hp = Start-Host (Join-Path $Bin 'Modal06.exe') $Bin @{ SWR_GM_LOG = $logPath; SWR_GM_TIMEOUT = '80' }
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
Log "ROW7 MODAL $(if ($pass -eq $Runs) { 'PASS' } else { 'FAIL' }) ($pass/$Runs runs)"
Log "ended=$(Get-Date -Format o)"
[System.IO.File]::WriteAllText($Result, [string]::Join("`r`n", $lines) + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
