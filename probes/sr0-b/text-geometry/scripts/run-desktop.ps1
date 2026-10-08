# SR0-B text-geometry desktop run. Executed by a one-shot interactive scheduled task (user adrds).
# Launches sr0b-text-geometry.exe in the interactive desktop session, drives it with UI Automation
# for each width phase, compares UIA rects with app paint/AX rects, writes result.json, then
# unregisters its own scheduled task.
param(
  [Parameter(Mandatory = $true)][string]$Exe,
  [Parameter(Mandatory = $true)][string]$RunDir,
  [Parameter(Mandatory = $true)][string]$ResultPath,
  [Parameter(Mandatory = $true)][string]$TaskName
)
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SR0BTG {
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
'@

$null = [SR0BTG]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))   # per-monitor v2: UIA reports physical px

$LogPath = Join-Path $RunDir 'app.log'
$StderrPath = Join-Path $RunDir 'stderr.log'
New-Item -ItemType Directory -Force $RunDir | Out-Null
$checks = New-Object System.Collections.ArrayList
$phaseOut = New-Object System.Collections.ArrayList
$info = [ordered]@{ started = (Get-Date).ToString('o'); exe = $Exe; runDir = $RunDir; host = $env:COMPUTERNAME; user = $env:USERNAME; session = (Get-Process -Id $PID).SessionId }

function Add-Check([string]$name, [bool]$pass, [string]$detail) {
  [void]$script:checks.Add([pscustomobject]@{ name = $name; status = $(if ($pass) { 'PASS' } else { 'FAIL' }); detail = $detail })
}

function Read-Log {
  try {
    $fs = [System.IO.File]::Open($script:LogPath, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object System.IO.StreamReader($fs)
    $t = $sr.ReadToEnd(); $sr.Close(); $fs.Close(); return $t
  } catch { return '' }
}

function Wait-Log([string]$pattern, [int]$seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  while ((Get-Date) -lt $deadline) {
    $t = Read-Log
    if ($t -match $pattern) { return $t }
    Start-Sleep -Milliseconds 100
  }
  return (Read-Log)
}

function Parse-Rects([string]$s) {
  $out = @()
  if ([string]::IsNullOrEmpty($s) -or $s -eq 'none') { return ,$out }
  foreach ($part in $s.Split('|')) {
    $v = [double[]]($part.Split(',') | ForEach-Object { [double]$_ })
    $out += ,$v
  }
  return ,$out
}

function Get-Field([string]$log, [string]$kind, [int]$phase, [int]$r) {
  foreach ($line in $log -split "`n") {
    if ($line.StartsWith("$kind phase=$phase r=$r ")) {
      $i = $line.IndexOf(' rects=')
      if ($i -ge 0) { return $line.Substring($i + 7).Trim() }
    }
  }
  return $null
}

function Max-RectErr($a, $b) {
  if ($a.Count -ne $b.Count) { return [double]::PositiveInfinity }
  $m = 0.0
  for ($i = 0; $i -lt $a.Count; $i++) {
    for ($k = 0; $k -lt 4; $k++) {
      $d = [math]::Abs($a[$i][$k] - $b[$i][$k])
      if ($d -gt $m) { $m = $d }
    }
  }
  return $m
}

function Uia-Rects($range, [double]$cx, [double]$cy) {
  $out = @()
  $rs = $range.GetBoundingRectangles()
  if ($rs -ne $null) {
    foreach ($rc in $rs) { $out += ,([double[]]@(($rc.X - $cx), ($rc.Y - $cy), $rc.Width, $rc.Height)) }
  }
  return ,$out
}

function Fmt-Rects($rs) {
  if ($rs.Count -eq 0) { return 'none' }
  return (($rs | ForEach-Object { ($_ | ForEach-Object { '{0:N2}' -f $_ }) -join ',' }) -join ' | ')
}

$TU_CHAR = [System.Windows.Automation.Text.TextUnit]::Character
$TU_WORD = [System.Windows.Automation.Text.TextUnit]::Word
$EP_START = [System.Windows.Automation.Text.TextPatternRangeEndpoint]::Start
$EP_END = [System.Windows.Automation.Text.TextPatternRangeEndpoint]::End

function Range-At($tp, [int]$a, [int]$b, [int]$n) {
  $r = $tp.DocumentRange.Clone()
  [void]$r.MoveEndpointByUnit($script:EP_START, $script:TU_CHAR, $a)
  [void]$r.MoveEndpointByUnit($script:EP_END, $script:TU_CHAR, ($b - $n))
  return $r
}

function Degenerate-Start($tp, [int]$n) {
  $r = $tp.DocumentRange.Clone()
  [void]$r.MoveEndpointByUnit($script:EP_END, $script:TU_CHAR, (-$n))
  return $r
}

function Count-Moves($tp, $unit, [int]$n) {
  $r = Degenerate-Start $tp $n
  $cnt = 0
  for ($k = 0; $k -lt ($n + 5); $k++) {
    $m = $r.Move($unit, 1)
    if ($m -eq 0) { break }
    $cnt++
  }
  return $cnt
}

$proc = $null
$clientX = 0.0; $clientY = 0.0
try {
  # ---- expectations from the app's START/EXPECT/RANGE lines (log written before the window)
  $env:SR0B_TG_LOG = $LogPath
  $env:SR0B_TG_RUN = $RunDir
  $proc = Start-Process -FilePath $Exe -PassThru -WindowStyle Normal `
    -RedirectStandardError $StderrPath -RedirectStandardOutput (Join-Path $RunDir 'stdout.log')
  $hwnd = [IntPtr]::Zero
  for ($i = 0; $i -lt 200 -and $hwnd -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 200; $proc.Refresh()
    if ($proc.HasExited) { break }
    $hwnd = $proc.MainWindowHandle
  }
  $info.exitedEarly = $proc.HasExited
  $info.hwnd = $hwnd.ToInt64()
  if ($hwnd -eq [IntPtr]::Zero) { throw 'no main window for sr0b-text-geometry' }

  $startLog = Wait-Log 'START pid=' 30
  $dpi = [SR0BTG]::GetDpiForWindow($hwnd)
  $info.dpi = $dpi
  $info.scaleFromDpi = $dpi / 96.0
  $pt = New-Object SR0BTG+POINT
  $pt.X = 0; $pt.Y = 0
  [void][SR0BTG]::ClientToScreen($hwnd, [ref]$pt)
  $clientX = [double]$pt.X; $clientY = [double]$pt.Y
  $info.clientOrigin = "$clientX,$clientY"
  $info.windowVisible = [SR0BTG]::IsWindowVisible($hwnd)

  $text = ([regex]::Match($startLog, 'text=(.*)')).Groups[1].Value.TrimEnd("`r")
  $expChars = [int]([regex]::Match($startLog, 'EXPECT chars=(\d+)')).Groups[1].Value
  $expWords = [int]([regex]::Match($startLog, 'EXPECT chars=\d+ words=(\d+)')).Groups[1].Value
  $expFirst = ([regex]::Match($startLog, 'firstword=(.*)')).Groups[1].Value.TrimEnd("`r")
  $ranges = @()
  foreach ($line in $startLog -split "`n") {
    if ($line -match '^RANGE (\d+) a=(\d+) b=(\d+) label=(.*?) text=(.*)$') {
      $ranges += [pscustomobject]@{ i = [int]$matches[1]; a = [int]$matches[2]; b = [int]$matches[3]; label = $matches[4]; text = $matches[5].TrimEnd("`r") }
    }
  }
  $info.expChars = $expChars; $info.expWords = $expWords; $info.expFirst = $expFirst; $info.ranges = $ranges.Count

  # ---- UI Automation: find the input and its TextPattern
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
  $nameCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'SR0-B text geometry input')
  $edit = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $nameCond)
  if ($edit -eq $null) { throw 'UIA: input element not found' }
  $patterns = ($edit.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
  $info.controlType = $edit.Current.ControlType.ProgrammaticName
  $info.patterns = ($patterns -join ',')
  Add-Check 'TextPattern present' ($patterns -contains 'TextPatternIdentifiers.Pattern') ("control=$($info.controlType) patterns=$($info.patterns)")
  $tp = $edit.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)

  $docText = $tp.DocumentRange.GetText(-1)
  Add-Check 'document text equals TEXT' ($docText -eq $text) ("uia_len=$($docText.Length) expected_len=$($text.Length)")

  $selectLine = $null
  for ($p = 0; $p -lt 5; $p++) {
    $log = Wait-Log ("PHASE $p ready") 60
    if ($log -notmatch "PHASE $p ready") { Add-Check "phase$p reached" $false 'app did not reach ready'; break }
    $commitLine = ([regex]::Match($log, "COMMIT phase=Some\($p\) version=\d+ width=([\d\.]+) scale=([\d\.]+) dpi=([\d\.]+) line0_w_phys=([\d\.]+) expect_phys=([\d\.]+)"))
    $width = $commitLine.Groups[1].Value; $scale = [double]$commitLine.Groups[2].Value
    $appDpi = [double]$commitLine.Groups[3].Value
    $pd = [pscustomobject]@{ phase = $p; width = $width; scale = $scale; appDpi = $appDpi; line0Phys = $commitLine.Groups[4].Value; line0Expect = $commitLine.Groups[5].Value }

    # Char and word navigation
    $charCount = Count-Moves $tp $TU_CHAR $expChars
    $wordCount = Count-Moves $tp $TU_WORD $expChars
    $dg = Degenerate-Start $tp $expChars
    [void]$dg.MoveEndpointByUnit($EP_END, $TU_CHAR, 1)
    $firstChar = $dg.GetText(-1)
    $dw = Degenerate-Start $tp $expChars
    $dw.ExpandToEnclosingUnit($TU_WORD)
    $firstWord = $dw.GetText(-1)
    Add-Check "phase$p char navigation" (($charCount -eq [int]$expChars) -and ($firstChar -eq $text.Substring(0, 1))) ("moves=$charCount expected=$expChars first_char_uia='$firstChar'")
    Add-Check "phase$p word navigation" (($wordCount -eq [int]$expWords) -and ($firstWord -eq $expFirst)) ("word_moves=$wordCount expected=$expWords first_word_uia='$firstWord' expected='$expFirst'")

    # Range text and rects for the 5 samples
    $maxPaint = 0.0; $maxAx = 0.0; $rangeDetail = @()
    $rangeOk = $true
    foreach ($rg in $ranges) {
      $r = Range-At $tp $rg.a $rg.b $expChars
      $gotText = $r.GetText(-1)
      $uiaR = Uia-Rects $r $clientX $clientY
      $paintR = Parse-Rects (Get-Field $log 'PAINT' $p $rg.i)
      $axR = Parse-Rects (Get-Field $log 'AX' $p $rg.i)
      $ep = Max-RectErr $uiaR $paintR
      $ea = Max-RectErr $uiaR $axR
      $textOk = ($gotText -eq $rg.text)
      if ($ep -gt $maxPaint) { $maxPaint = $ep }
      if ($ea -gt $maxAx) { $maxAx = $ea }
      if (-not ($textOk -and $ep -le 1.0 -and $ea -le 1.0)) { $rangeOk = $false }
      $rangeDetail += "[$($rg.label)] text_ok=$textOk uia=$(Fmt-Rects $uiaR) paint=$(Fmt-Rects $paintR) ax=$(Fmt-Rects $axR) err_paint=$('{0:N2}' -f $ep) err_ax=$('{0:N2}' -f $ea)"
      $pd | Add-Member -NotePropertyName "range$($rg.i)" -NotePropertyValue ([pscustomobject]@{ label = $rg.label; uia = @($uiaR | ForEach-Object { ,$_ }); paint = @($paintR | ForEach-Object { ,$_ }); ax = @($axR | ForEach-Object { ,$_ }); text = $gotText }) -Force
    }
    Add-Check "phase$p rect agreement (UIA vs paint, UIA vs AX, <=1px)" $rangeOk ("width=$width scale=$scale max_err_paint=$('{0:N2}' -f $maxPaint) max_err_ax=$('{0:N2}' -f $maxAx) :: " + ($rangeDetail -join ' ; '))

    # Self-check result from the app (paint vs commit, hit tests, AX vs commit)
    $sc = ([regex]::Match($log, "SELFCHECK phase=$p (.*)")).Groups[1].Value
    Add-Check "phase$p app self-check (paint/hit/AX)" ($sc -match 'pass=true') $sc

    # Caret and selection (phase 0 only for the caret; selection persists across phases)
    if ($p -eq 0) {
      $sel = $tp.GetSelection()
      $selCount = if ($sel -eq $null) { 0 } else { $sel.Count }
      $caretText = if ($selCount -gt 0) { $sel[0].GetText(-1) } else { '<none>' }
      $caretRect = if ($selCount -gt 0) { Uia-Rects $sel[0] $clientX $clientY } else { @() }
      $appCaret = Get-Field $log 'CARET' 0 0
      $caretLine = ([regex]::Match($log, 'CARET phase=0 idx=(\d+) commit_rect=([^ ]+) ax_rect=')).Groups
      $cr = Parse-Rects $caretLine[2].Value
      $caretOk = ($selCount -eq 1) -and ($caretText -eq '') -and ($caretRect.Count -ge 1) -and ([math]::Abs($caretRect[0][0] - $cr[0][0]) -le 1.0) -and ([math]::Abs($caretRect[0][1] - $cr[0][1]) -le 1.0)
      Add-Check 'caret bounds (phase0, degenerate selection)' $caretOk ("caret_idx_app=$($caretLine[1].Value) uia_selection_count=$selCount uia_text='$caretText' uia_rect=$(Fmt-Rects $caretRect) app_commit_rect=$($caretLine[2].Value)")

      $a0 = $ranges[0]
      $selRange = Range-At $tp $a0.a $a0.b $expChars
      $selRange.Select()
      $applied = Wait-Log 'APPLY select anchor=' 8
      $selectLine = ([regex]::Match($applied, 'APPLY select anchor=\d+ focus=\d+')).Value
      $actionLine = ([regex]::Match($applied, 'ACTION Select \{[^\n]*SetTextSelection[^\n]*|ACTION Select[^\n]*')).Value
      Start-Sleep -Milliseconds 400
      $sel2 = $tp.GetSelection()
      $selText = if ($sel2 -ne $null -and $sel2.Count -gt 0) { $sel2[0].GetText(-1) } else { '<none>' }
      $setSelLogged = ($applied -match 'ACTION Select') -and ($applied -match 'APPLY select')
      Add-Check 'selection set via TextPatternRange.Select (SetTextSelection logged and applied)' ($setSelLogged -and ($selText -eq $a0.text)) ("app=[$selectLine] action_logged=$setSelLogged uia_selection_text='$selText' expected='$($a0.text)'")
    } else {
      $sel3 = $tp.GetSelection()
      $selText3 = if ($sel3 -ne $null -and $sel3.Count -gt 0) { $sel3[0].GetText(-1) } else { '<none>' }
      Add-Check "phase$p selection persists across width change" ($selText3 -eq $ranges[0].text) ("uia_selection_text='$selText3' expected='$($ranges[0].text)' width=$width")
    }
    [void]$phaseOut.Add($pd)

    Set-Content -Path (Join-Path $RunDir "ack-$p.txt") -Value 'ack' -Encoding ascii
    Start-Sleep -Milliseconds 300
  }

  $done = Wait-Log 'DONE' 30
  Add-Check 'app ran all phases and shut down' ($done -match 'DONE') ('DONE line present=' + ($done -match 'DONE'))
  $cache = ([regex]::Match($done, 'CACHE hits=(\d+) misses=(\d+) measure_calls=(\d+)'))
  $cacheOk = ($cache.Success -and $cache.Groups[1].Value -eq '2' -and $cache.Groups[2].Value -eq '3')
  Add-Check 'measurement sync & cached (3 misses, 2 cache hits)' $cacheOk ($cache.Value)
  $measureLines = ([regex]::Matches($done, 'MEASURE phase=\S+ width=\S+ scale=\S+ cache=(hit|miss) sync=true')).Count
  Add-Check 'all measurements synchronous (on UI thread, before commit)' ($measureLines -eq 5) ("MEASURE lines=$measureLines")
  $commitMatches = [regex]::Matches($done, 'COMMIT phase=\S+ version=\d+ width=([\d\.]+) scale=([\d\.]+) dpi=([\d\.]+) line0_w_phys=([\d\.]+) expect_phys=([\d\.]+)')
  $physOk = $true; $physDetail = @()
  foreach ($m in $commitMatches) {
    $lw = [double]$m.Groups[4].Value; $le = [double]$m.Groups[5].Value
    if ([math]::Abs($lw - $le) -gt 0.01) { $physOk = $false }
    $physDetail += "w=$($m.Groups[1].Value) scale=$($m.Groups[2].Value) line0_phys=$lw expect=$le"
  }
  Add-Check 'physical-px commit (logical x scale_factor, per commit)' ($physOk -and $commitMatches.Count -ge 5) ($physDetail -join '; ')
  $appScale = if ($commitMatches.Count -gt 0) { [double]$commitMatches[0].Groups[2].Value } else { 0.0 }
  $dpiOk = ([math]::Abs($appScale * 96.0 - $info.dpi) -le 0.5)
  Add-Check 'DPI recorded and matches window scale' $dpiOk ("GetDpiForWindow=$($info.dpi) app_scale=$appScale (dpi=$($appScale*96))")
  $dispatchAct = ([regex]::Matches($done, 'ACTION Select')).Count
  Add-Check 'AccessKit action requests logged' ($dispatchAct -ge 1) ("ACTION Select lines=$dispatchAct")
} catch {
  Add-Check 'run completed without exception' $false ($_.Exception.Message)
} finally {
  if ($proc -ne $null) {
    $proc.Refresh()
    if (-not $proc.HasExited) { $proc.WaitForExit(20000) | Out-Null }
    if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force; $info.killed = $true }
    $info.exitCode = $proc.ExitCode
  }
  $overall = (($checks | Where-Object { $_.status -ne 'PASS' }).Count -eq 0)
  $info.ended = (Get-Date).ToString('o')
  $result = [ordered]@{ info = $info; overall = $(if ($overall) { 'PASS' } else { 'FAIL' }); checks = $checks; phases = $phaseOut }
  $json = $result | ConvertTo-Json -Depth 8
  [System.IO.File]::WriteAllText($ResultPath, $json, (New-Object System.Text.UTF8Encoding($false)))
  [System.IO.File]::WriteAllText((Join-Path $RunDir 'result.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
  try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop } catch { }
}
