# Row 6 driver: runs TextGeom06.exe N times from INSIDE an interactive desktop session (one-shot scheduled task, see
# schedule.ps1) and reads the text back through UI Automation. Window-targeted only: UIA TextPattern, no input injection.
# Per run: 35 checks equivalent to probes/sr0-b/text-geometry run 4 (same names, same tolerances; "paint" is the cell
# geometry the renderer paints from, which is all the run-4 probe compared too) + the multi-paragraph checks for 4df7e67
# (names start with "B ") + the host's own checks (HC lines, names start with "host:").
param(
  [string]$Base = 'D:\Claude\sr0-geomodal',
  [string]$Bin = '',
  [string]$OutDir = '',
  [string]$Result = '',
  [int]$Runs = 20,
  [switch]$DryRun
)
. (Join-Path $PSScriptRoot 'common.ps1')
if (-not $Bin) { $Bin = Join-Path $Base 'bin' }
if (-not $OutDir) { $OutDir = Join-Path $Base 'out\textgeom' }
if (-not $Result) { $Result = Join-Path $Base 'result-textgeom06final.txt' }

$TU_CHAR = [System.Windows.Automation.Text.TextUnit]::Character
$TU_WORD = [System.Windows.Automation.Text.TextUnit]::Word
$TU_LINE = [System.Windows.Automation.Text.TextUnit]::Line
$EP_START = [System.Windows.Automation.Text.TextPatternRangeEndpoint]::Start
$EP_END = [System.Windows.Automation.Text.TextPatternRangeEndpoint]::End

# ---------------------------------------------------------------- helpers (run-4 semantics)
function Parse-Rects([string]$s) {
  $out = @()
  if ([string]::IsNullOrEmpty($s) -or $s -eq 'none') { return ,$out }
  foreach ($part in $s.Split('|')) {
    $v = [double[]]($part.Split(',') | ForEach-Object { [double]$_ })
    $out += ,$v
  }
  return ,$out
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

# Managed rectangles; System.Windows.Rect.Empty (zero-width rect converted by the wrapper) means "no rectangle", skipped.
function Uia-Rects($range, [double]$cx, [double]$cy) {
  $out = @()
  $rs = $range.GetBoundingRectangles()
  if ($rs -ne $null) {
    foreach ($rc in $rs) {
      if ($rc.IsEmpty -or $rc.Width -lt 0.01) { continue }
      $out += ,([double[]]@(($rc.X - $cx), ($rc.Y - $cy), $rc.Width, $rc.Height))
    }
  }
  return ,$out
}

# Raw provider array (x,y,w,h per rectangle): the managed wrapper hides zero-width rectangles (degenerate ranges, newlines).
$script:RawGet = [System.Windows.Automation.TextPattern].Assembly.GetType('MS.Internal.Automation.UiaCoreApi').GetMethod('RawTextRange_GetBoundingRectangles', [Reflection.BindingFlags]'Static,NonPublic,Public')
$script:RangeHandle = [System.Windows.Automation.Text.TextPatternRange].GetField('_hTextRange', [Reflection.BindingFlags]'Instance,NonPublic')
function Raw-Rects($range, [double]$cx, [double]$cy) {
  try {
    $h = $script:RangeHandle.GetValue($range)
    $a = New-Object object[] 2
    $a[0] = $h
    $hr = $script:RawGet.Invoke($null, $a)
    $d = $a[1]
    $out = @()
    if ($d -ne $null) {
      for ($i = 0; $i + 3 -lt $d.Length; $i += 4) { $out += ,([double[]]@(($d[$i] - $cx), ($d[$i + 1] - $cy), $d[$i + 2], $d[$i + 3])) }
    }
    return ,$out
  } catch { return $null }
}

function Get-Cps([string]$t) {
  $cps = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $t.Length; $i++) {
    if ([char]::IsHighSurrogate($t[$i]) -and ($i + 1) -lt $t.Length) { [void]$cps.Add($t.Substring($i, 2)); $i++ }
    else { [void]$cps.Add($t[$i].ToString()) }
  }
  return ,$cps
}
function Is-Wide([string]$s) { return ([char]::ConvertToUtf32($s, 0) -ge 0x3000) }
function Is-Ws([string]$s) { return ($s.Length -eq 1 -and [char]::IsWhiteSpace($s[0])) }

# Word stops: the host/text.rs word-start rule PLUS accesskit_consumer 0.39.1 text.rs `forward_to_word_start`, which also stops at the
# start of every paragraph (a run whose predecessor ends in '\n'), even an empty one (a blank line, the empty line after a trailing
# newline); then the end of the document as the final stop. (Source read 10 Oct on docs.rs; for text without a newline this is the
# run-4 rule unchanged.)
function Word-Stops($cps) {
  $n = $cps.Count
  $stops = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $n; $i++) {
    $c = $cps[$i]
    $para = ($i -eq 0) -or ($cps[$i - 1] -ceq "`n")
    if ((Is-Ws $c) -and -not $para) { continue }
    $start = ($i -eq 0) -or $para
    if (-not $start) { $p = $cps[$i - 1]; $start = ((Is-Ws $p) -or (Is-Wide $c) -or (Is-Wide $p)) }
    if ($start) { [void]$stops.Add($i) }
  }
  [void]$stops.Add($n)
  return ,$stops
}

function Fmt-Rects($rs) {
  if ($rs -eq $null -or $rs.Count -eq 0) { return 'none' }
  return (($rs | ForEach-Object { ($_ | ForEach-Object { '{0:N2}' -f $_ }) -join ',' }) -join ' | ')
}

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

function Get-SelText($tp) {
  try { $s = $tp.GetSelection(); if ($s -ne $null -and $s.Count -gt 0) { return $s[0].GetText(-1) } } catch { }
  return '<none>'
}

# x/y/h within tol of the expected caret rectangle, width from 0 to the caret thickness (AccessKit: zero-width box)
function Test-CaretRect($raw, $exp, [double]$tol) {
  if ($raw -eq $null -or $raw.Count -lt 1) { return $false }
  $r0 = $raw[0]
  return ([math]::Abs($r0[0] - $exp[0]) -le $tol) -and ([math]::Abs($r0[1] - $exp[1]) -le $tol) -and ([math]::Abs($r0[3] - $exp[3]) -le $tol) -and ($r0[2] -ge 0) -and ($r0[2] -le ($exp[2] + $tol))
}

function Add-Check([string]$name, [bool]$pass, [string]$detail) {
  [void]$script:checks.Add([pscustomobject]@{ name = $name; status = $(if ($pass) { 'PASS' } else { 'FAIL' }); detail = $detail })
}

# Polls until UIA shows the layout the host just committed (the renderer publishes AccessKit at most every 100 ms).
function Wait-Converged($tp, [string]$expectText, $expectRects0, $range0, [int]$n, [double]$cx, [double]$cy, [double]$seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $seconds) {
    try {
      $t = $tp.DocumentRange.GetText(-1)
      if ($t -ceq $expectText) {
        $r = Range-At $tp $range0.a $range0.b $n
        $u = Uia-Rects $r $cx $cy
        if ((Max-RectErr $u $expectRects0) -le 1.0) { return [int]$sw.ElapsedMilliseconds }
      }
    } catch { }
    Start-Sleep -Milliseconds 50
  }
  return -1
}

# Polls until the UIA selection text equals the expectation (the selection is republished with the next AccessKit update).
function Wait-SelText($tp, [string]$expect, [double]$seconds) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $t = ''
  while ($sw.Elapsed.TotalSeconds -lt $seconds) {
    $t = Get-SelText $tp
    if ($t -ceq $expect) { return $t }
    Start-Sleep -Milliseconds 50
  }
  return $t
}

function Wait-Tail([string]$logPath, [int]$from, [string]$pattern, [double]$seconds) {
  $deadline = (Get-Date).AddSeconds($seconds)
  $t = ''
  while ((Get-Date) -lt $deadline) {
    $all = Read-Shared $logPath
    if ($all.Length -gt $from) { $t = $all.Substring($from); if ($t -match "(?m)$pattern") { return $t } }
    Start-Sleep -Milliseconds 40
  }
  return $t
}

function Last-Match([string]$text, [string]$pattern) {
  $ms = [regex]::Matches($text, $pattern)
  if ($ms.Count -eq 0) { return $null }
  return $ms[$ms.Count - 1]
}

# ---------------------------------------------------------------- one run
function Invoke-TextRun([int]$n) {
  $script:checks = New-Object System.Collections.ArrayList
  $runDir = Join-Path $OutDir ('run-{0:D2}' -f $n)
  New-Item -ItemType Directory -Force $runDir | Out-Null
  $logPath = Join-Path $runDir 'host.log'
  $info = [ordered]@{ run = $n; started = (Get-Date).ToString('o'); runDir = $runDir }
  $hp = $null
  $total = [Diagnostics.Stopwatch]::StartNew()
  try {
    $hp = Start-Host (Join-Path $Bin 'TextGeom06.exe') $Bin @{ SWR_GM_LOG = $logPath; SWR_GM_RUNDIR = $runDir; SWR_GM_TIMEOUT = '100' }
    $proc = $hp.Proc
    $hwnd = Wait-MainWindow $proc 30
    $info.hwnd = $hwnd.ToInt64()
    if ($hwnd -eq [IntPtr]::Zero) { throw 'no main window for TextGeom06' }
    $startLog = Wait-Log $logPath '^PHASES ' 30
    if ($startLog -notmatch '(?m)^PHASES ') { throw 'host never logged PHASES' }
    $dpi = [GMWin]::GetDpiForWindow($hwnd)
    $pt = New-Object GMWin+POINT
    [void][GMWin]::ClientToScreen($hwnd, [ref]$pt)
    $cx = [double]$pt.X; $cy = [double]$pt.Y
    $info.dpi = $dpi; $info.clientOrigin = "$cx,$cy"; $info.windowVisible = [GMWin]::IsWindowVisible($hwnd)

    # ---- the host's declared expectations
    $variants = @{}
    foreach ($m in [regex]::Matches($startLog, '(?m)^VARIANT (\d+) name=(\w+) chars=(\d+) bytes=(\d+) utf16=(\d+) words=(\d+) firstword=(.*?) text=(.*?)\r?$')) {
      $text = Unesc $m.Groups[8].Value
      $cps = Get-Cps $text
      $variants[[int]$m.Groups[1].Value] = [pscustomobject]@{
        Chars = [int]$m.Groups[3].Value; Bytes = [int]$m.Groups[4].Value; Utf16 = [int]$m.Groups[5].Value; Words = [int]$m.Groups[6].Value
        First = (Unesc $m.Groups[7].Value); Text = $text; Cps = $cps; Stops = (Word-Stops $cps)
        Ranges = New-Object System.Collections.ArrayList; Carets = @{}; Selects = @{}
      }
    }
    foreach ($m in [regex]::Matches($startLog, '(?m)^RANGE (\d+) (\d+) a=(\d+) b=(\d+) label=(.*?) text=(.*?)\r?$')) {
      [void]$variants[[int]$m.Groups[1].Value].Ranges.Add([pscustomobject]@{ i = [int]$m.Groups[2].Value; a = [int]$m.Groups[3].Value; b = [int]$m.Groups[4].Value; label = (Unesc $m.Groups[5].Value); text = (Unesc $m.Groups[6].Value) })
    }
    foreach ($m in [regex]::Matches($startLog, '(?m)^CARETIDX (\d+) name=(\w+) idx=(\d+)')) { $variants[[int]$m.Groups[1].Value].Carets[$m.Groups[2].Value] = [int]$m.Groups[3].Value }
    foreach ($m in [regex]::Matches($startLog, '(?m)^SELECT (\d+) name=(\w+) a=(\d+) b=(\d+) text=(.*?)\r?$')) {
      $variants[[int]$m.Groups[1].Value].Selects[$m.Groups[2].Value] = [pscustomobject]@{ a = [int]$m.Groups[3].Value; b = [int]$m.Groups[4].Value; text = (Unesc $m.Groups[5].Value) }
    }
    $phaseSpecs = ([regex]::Match($startLog, '(?m)^PHASES (\S+)')).Groups[1].Value.Split(',')
    $phaseCount = $phaseSpecs.Count
    $info.phases = $phaseCount
    $A = $variants[0]; $B = $variants[1]
    if ($A -eq $null -or $B -eq $null) { throw 'host did not declare both variants' }
    $info.expA = "chars=$($A.Chars) bytes=$($A.Bytes) utf16=$($A.Utf16) words=$($A.Words)"; $info.expB = "chars=$($B.Chars) bytes=$($B.Bytes) utf16=$($B.Utf16)"
    foreach ($V in @($A, $B)) { if ($V.Cps.Count -ne $V.Chars) { throw "code point count $($V.Cps.Count) != host chars $($V.Chars)" } }

    # ---- UI Automation: the input element and its TextPattern
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
    $idCond = New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'textgeom/input')),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)))
    $edit = $null
    for ($k = 0; $k -lt 80 -and $edit -eq $null; $k++) { $edit = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $idCond); if ($edit -eq $null) { Start-Sleep -Milliseconds 125 } }
    if ($edit -eq $null) { throw 'UIA: textgeom/input element not found' }
    $patterns = ($edit.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName })
    $info.controlType = $edit.Current.ControlType.ProgrammaticName
    $info.patterns = ($patterns -join ',')
    Add-Check 'TextPattern present' ($patterns -contains 'TextPatternIdentifiers.Pattern') "control=$($info.controlType) patterns=$($info.patterns)"
    $tp = $edit.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)

    $hostDpiSeen = 0.0
    $cacheSeen = @{}
    $physSeen = @()
    $commitLines = @()
    for ($p = 0; $p -lt $phaseCount; $p++) {
      $log = Wait-Log $logPath "^PHASE $p ready" 60
      if ($log -notmatch "(?m)^PHASE $p ready") { Add-Check "phase$p reached" $false 'host did not reach ready'; break }
      $cm = [regex]::Match($log, "(?m)^COMMIT phase=$p version=(\d+) variant=(\d+) width=(\d+) scale=([\d\.]+) dpi=([\d\.]+) maxw_phys=([\d\.]+) lines=(\d+) chars=(\d+) cache=(\w+) line0_w_phys=([\d\.\-]+) expect_phys=([\d\.\-]+)")
      if (-not $cm.Success) { Add-Check "phase$p COMMIT line" $false 'missing'; break }
      $vi = [int]$cm.Groups[2].Value; $V = $variants[$vi]; $width = $cm.Groups[3].Value
      $hostDpiSeen = [double]$cm.Groups[5].Value
      $cacheSeen[$p] = $cm.Groups[9].Value
      $commitLines += ,@([double]$cm.Groups[10].Value, [double]$cm.Groups[11].Value, $cm.Groups[3].Value, $cm.Groups[4].Value)
      $nch = $V.Chars
      $cellsR0 = Parse-Rects (([regex]::Match($log, "(?m)^RECT phase=$p r=0 kind=cells rects=(.*?)\r?$")).Groups[1].Value)
      $conv = Wait-Converged $tp $V.Text $cellsR0 $V.Ranges[0] $nch $cx $cy 8
      $docText = $tp.DocumentRange.GetText(-1)
      $pre = "variant=$($V.Chars -as [string])c width=$width converge_ms=$conv"

      # ---- navigation (both variants): characters, words
      $charCount = Count-Moves $tp $TU_CHAR $nch
      $wordCount = Count-Moves $tp $TU_WORD $nch
      $dg = Degenerate-Start $tp $nch
      [void]$dg.MoveEndpointByUnit($EP_END, $TU_CHAR, 1)
      $firstChar = $dg.GetText(-1)
      $dw = Degenerate-Start $tp $nch
      $dw.ExpandToEnclosingUnit($TU_WORD)
      $firstWord = $dw.GetText(-1)
      $expMoves = $V.Stops.Count - 1
      $wk = Degenerate-Start $tp $nch
      $seqBad = New-Object System.Collections.ArrayList
      $wkMoves = 0
      for ($k = 1; $k -lt $V.Stops.Count; $k++) {
        if ($wk.Move($TU_WORD, 1) -eq 0) { [void]$seqBad.Add("move$k=0"); break }
        $wkMoves++
        $pk = $wk.Clone(); $pk.ExpandToEnclosingUnit($TU_CHAR)
        $got = $pk.GetText(-1)
        $idx = $V.Stops[$k]
        $want = if ($idx -ge $nch) { '' } else { $V.Cps[$idx] }
        if ($got -cne $want) { [void]$seqBad.Add("stop$k@$idx got='$got' want='$want'") }
      }
      $wordOk = (($wordCount -eq $expMoves) -and ($wkMoves -eq $expMoves) -and ($seqBad.Count -eq 0) -and ($firstWord -ceq $V.First))
      $charOk = (($charCount -eq $nch) -and ($firstChar -ceq $V.Cps[0]))
      $selfLine = ([regex]::Match($log, "(?m)^SELFCHECK phase=$p (.*?)\r?$")).Groups[1].Value
      $physLine = ([regex]::Match($log, "(?m)^PHYS phase=$p (.*?)\r?$")).Groups[1].Value
      $physSeen += ,@($p, ($physLine -match 'pass=true'), $physLine)

      # ---- sample ranges: text and rectangles, UIA vs cells (what is painted) and vs the committed AX runs
      $maxCells = 0.0; $maxAx = 0.0; $rangeDetail = @(); $rangeOk = $true
      foreach ($rg in $V.Ranges) {
        $r = Range-At $tp $rg.a $rg.b $nch
        $gotText = $r.GetText(-1)
        $uiaR = Uia-Rects $r $cx $cy
        $cellsR = Parse-Rects (([regex]::Match($log, "(?m)^RECT phase=$p r=$($rg.i) kind=cells rects=(.*?)\r?$")).Groups[1].Value)
        $axR = Parse-Rects (([regex]::Match($log, "(?m)^RECT phase=$p r=$($rg.i) kind=ax rects=(.*?)\r?$")).Groups[1].Value)
        $ec = Max-RectErr $uiaR $cellsR
        $ea = Max-RectErr $uiaR $axR
        $textOk = ($gotText -ceq $rg.text)
        if ($ec -gt $maxCells) { $maxCells = $ec }
        if ($ea -gt $maxAx) { $maxAx = $ea }
        if (-not ($textOk -and $ec -le 1.0 -and $ea -le 1.0)) { $rangeOk = $false }
        $rangeDetail += "[$(($rg.label -replace "`n",'\n'))] text_ok=$textOk uia=$(Fmt-Rects $uiaR) cells=$(Fmt-Rects $cellsR) ax=$(Fmt-Rects $axR) err_cells=$('{0:N2}' -f $ec) err_ax=$('{0:N2}' -f $ea)"
      }

      if ($vi -eq 0) {
        # ================= group A: the run-4 checks
        if ($p -eq 0) { Add-Check 'document text equals TEXT' ($docText -ceq $V.Text) "uia_len=$($docText.Length) expected_len=$($V.Text.Length) converge_ms=$conv" }
        Add-Check "phase$p char navigation" $charOk "moves=$charCount expected=$nch first_char_uia='$firstChar'"
        Add-Check "phase$p word navigation (boundaries + end of document)" $wordOk "word_moves=$wordCount expected=$expMoves (= $($expMoves - 1) word starts after index 0 + end-of-document) sequence_mismatches=[$($seqBad -join '; ')] first_word_uia='$firstWord' expected='$($V.First)'"
        Add-Check "phase$p rect agreement (UIA vs cells, UIA vs AX, <=1px)" $rangeOk "width=$width max_err_cells=$('{0:N2}' -f $maxCells) max_err_ax=$('{0:N2}' -f $maxAx) :: $($rangeDetail -join ' ; ')"
        Add-Check "phase$p app self-check (cells/AX/lines)" ($selfLine -match 'pass=true') $selfLine
        if ($p -eq 0) {
          # caret: the degenerate selection at "beta" (host caret rectangle) read through the raw provider array, and the one-character range
          $sel = $tp.GetSelection()
          $selCount = if ($sel -eq $null) { 0 } else { $sel.Count }
          $caretText = if ($selCount -gt 0) { $sel[0].GetText(-1) } else { '<none>' }
          $cl = [regex]::Match($log, "(?m)^CARET phase=0 idx=(\d+) rect=(\S+)")
          $ci = [int]$cl.Groups[1].Value
          $cr = Parse-Rects $cl.Groups[2].Value
          $dgR = Range-At $tp $ci $ci $nch
          $rawDg = Raw-Rects $dgR $cx $cy
          $rawSel = if ($selCount -gt 0) { Raw-Rects $sel[0] $cx $cy } else { $null }
          $managedDg = Uia-Rects $dgR $cx $cy
          $dgOk = ($selCount -eq 1) -and ($caretText -ceq '') -and (Test-CaretRect $rawDg $cr[0] 1.0)
          Add-Check 'caret: degenerate range reports caret rect (zero-width, raw provider array)' $dgOk "caret_idx_app=$ci uia_selection_count=$selCount uia_text='$caretText' raw_degenerate=$(if ($rawDg -eq $null) { 'unavailable' } else { Fmt-Rects $rawDg }) raw_selection=$(if ($rawSel -eq $null) { 'unavailable' } else { Fmt-Rects $rawSel }) managed_degenerate=$(Fmt-Rects $managedDg) app_caret=$($cl.Groups[2].Value)"
          $oneR = Range-At $tp $ci ($ci + 1) $nch
          $oneText = $oneR.GetText(-1)
          $oneRects = Uia-Rects $oneR $cx $cy
          $oneOk = ($oneRects.Count -ge 1) -and ($oneText -ceq $V.Cps[$ci]) -and ([math]::Abs($oneRects[0][0] - $cr[0][0]) -le 1.0) -and ([math]::Abs($oneRects[0][1] - $cr[0][1]) -le 1.0) -and ([math]::Abs($oneRects[0][3] - $cr[0][3]) -le 1.0)
          Add-Check 'caret location via one-character range matches app caret (<=1px)' $oneOk "caret_idx_app=$ci one_char_text='$oneText' one_char_rect=$(Fmt-Rects $oneRects) app_caret=$($cl.Groups[2].Value)"
          # selection through TextPatternRange.Select -> AccessKit SetTextSelection -> host event -> re-commit
          $s0 = $V.Selects['alpha']
          $before = (Read-Shared $logPath).Length
          (Range-At $tp $s0.a $s0.b $nch).Select()
          $applied = Wait-Tail $logPath $before "^APPLY select anchor=$($s0.a) focus=$($s0.b) phase=0" 8
          $selTxt = Wait-SelText $tp $s0.text 4
          $setSelLogged = ($applied -match "(?m)^ACTION setSelection node=3 anchor=$($s0.a) focus=$($s0.b)") -and ($applied -match "(?m)^APPLY select anchor=$($s0.a) focus=$($s0.b)")
          Add-Check 'selection set via TextPatternRange.Select (SetTextSelection logged and applied)' ($setSelLogged -and ($selTxt -ceq $s0.text)) "action_and_apply_logged=$setSelLogged uia_selection_text='$selTxt' expected='$($s0.text)'"
        } else {
          $selTxt3 = Wait-SelText $tp $V.Selects['alpha'].text 4
          Add-Check "phase$p selection persists across width change" ($selTxt3 -ceq $V.Selects['alpha'].text) "uia_selection_text='$selTxt3' expected='$($V.Selects['alpha'].text)' width=$width"
        }
      } else {
        # ================= group B: multi-paragraph text with newline cells (4df7e67)
        if ($p -eq 5) { Add-Check 'B document text equals the multi-paragraph TEXT (newline characters included)' ($docText -ceq $V.Text) "uia_len=$($docText.Length) expected_len=$($V.Text.Length) converge_ms=$conv" }
        Add-Check "B phase$p char navigation (each newline is one character)" $charOk "moves=$charCount expected=$nch first_char_uia='$firstChar'"
        Add-Check "B phase$p word navigation (boundaries + end of document)" $wordOk "word_moves=$wordCount expected=$expMoves sequence_mismatches=[$($seqBad -join '; ')] first_word_uia='$firstWord' expected='$($V.First)'"
        Add-Check "B phase$p rect agreement of sample ranges (UIA vs cells, UIA vs AX, <=1px)" $rangeOk "width=$width max_err_cells=$('{0:N2}' -f $maxCells) max_err_ax=$('{0:N2}' -f $maxAx) :: $($rangeDetail -join ' ; ')"
        # visual lines: ExpandToEnclosingUnit(Line) from the first character of each line must give that line's text and rectangle
        $lineBad = @(); $lineN = 0
        foreach ($lm in [regex]::Matches($log, "(?m)^LINE phase=$p k=(\d+) first=(-?\d+) count=(\d+) rect=(\S+) text=(.*?)\r?$")) {
          $k = [int]$lm.Groups[1].Value; $first = [int]$lm.Groups[2].Value; $cnt = [int]$lm.Groups[3].Value
          if ($cnt -le 0) { continue }
          $lineN++
          $exp = (Parse-Rects $lm.Groups[4].Value)[0]; $wantText = Unesc $lm.Groups[5].Value
          $lr = Range-At $tp $first ($first + 1) $nch
          $lr.ExpandToEnclosingUnit($TU_LINE)
          $lt = $lr.GetText(-1)
          if ($exp[2] -gt 0.5) { $ur = Uia-Rects $lr $cx $cy; $rectOk = ($ur.Count -ge 1) -and ((Max-RectErr @(,$ur[0]) @(,$exp)) -le 1.0) -and ($ur.Count -eq 1) }
          else { $rawL = Raw-Rects $lr $cx $cy; $rectOk = Test-CaretRect $rawL $exp 1.0 }
          if (($lt -cne $wantText) -or (-not $rectOk)) { $lineBad += "line$k text_ok=$($lt -ceq $wantText) rect_ok=$rectOk got='$(($lt -replace "`n",'\n'))' want='$(($wantText -replace "`n",'\n'))' exp=$(Fmt-Rects @(,$exp))" }
        }
        Add-Check "B phase$p visual lines: Line unit text and rectangle per line" (($lineBad.Count -eq 0) -and ($lineN -ge 5)) "lines_checked=$lineN bad=[$($lineBad -join ' ; ')]"
        # newline cells: the one-character range over each '\n' is the newline, zero width, at the end of its line (raw provider array)
        $nlBad = @(); $nlN = 0
        foreach ($nm in [regex]::Matches($log, "(?m)^NL phase=$p idx=(\d+) line=(\d+) rect=(\S+)")) {
          $idx = [int]$nm.Groups[1].Value; $exp = (Parse-Rects $nm.Groups[3].Value)[0]
          $nlN++
          $nr = Range-At $tp $idx ($idx + 1) $nch
          $nt = $nr.GetText(-1)
          $rawN = Raw-Rects $nr $cx $cy
          if (($nt -cne "`n") -or (-not (Test-CaretRect $rawN $exp 1.0))) { $nlBad += "idx$idx text_is_newline=$($nt -ceq "`n") raw=$(if ($rawN -eq $null) { 'unavailable' } else { Fmt-Rects $rawN }) exp=$(Fmt-Rects @(,$exp))" }
        }
        Add-Check "B phase$p newline cells: one-character range is the newline, zero width at the end of its line" (($nlBad.Count -eq 0) -and ($nlN -eq 4)) "newlines_checked=$nlN bad=[$($nlBad -join ' ; ')]"
        # the spanning selection set at the end of phase 5 must survive the width change; read it BEFORE the caret round trips below change the selection
        if ($p -ne 5) {
          $sp = $V.Selects['span']
          $selTxt4 = Wait-SelText $tp $sp.text 4
          Add-Check "B phase$p spanning selection persists across width change" ($selTxt4 -ceq $sp.text) "uia_selection_text='$(($selTxt4 -replace "`n",'\n'))' expected='$(($sp.text -replace "`n",'\n'))' width=$width"
        }
        # caret rectangles of the PUBLISHED selection: Select() a degenerate range at each named index (blank line, paragraph start, end of
        # the document after the trailing newline); the host maps the global character index to (run, character), re-commits and draws its
        # caret; UIA's selection rectangle (raw provider array) must be that caret. The raw rectangle of the client-built degenerate range is
        # reported alongside (informational: how the client normalizes a position on a line boundary is its own business).
        $lineMs = [regex]::Matches($log, "(?m)^LINE phase=$p k=(\d+) first=-?\d+ count=\d+ rect=(\S+) text=")
        $lastLineRect = (Parse-Rects $lineMs[$lineMs.Count - 1].Groups[2].Value)[0]
        $cxBad = @(); $cxN = 0; $cxInfo = @()
        foreach ($cm2 in [regex]::Matches($log, "(?m)^CARETX phase=$p name=(\w+) idx=(\d+) rect=(\S+)")) {
          $cidx = [int]$cm2.Groups[2].Value; $exp = (Parse-Rects $cm2.Groups[3].Value)[0]; $cname = $cm2.Groups[1].Value
          $cxN++
          $before = (Read-Shared $logPath).Length
          $dr = Range-At $tp $cidx $cidx $nch
          $rawDirect = Raw-Rects $dr $cx $cy
          $dr.Select()
          $applied = Wait-Tail $logPath $before "^CARET phase=$p idx=$cidx rect=" 8
          $okApply = $applied -match "(?m)^APPLY select anchor=$cidx focus=$cidx phase=$p"
          $hc = Last-Match $applied "(?m)^CARET phase=$p idx=$cidx rect=(\S+)"
          $hostCaret = if ($hc -ne $null) { (Parse-Rects $hc.Groups[1].Value)[0] } else { $null }
          $hostIsExp = ($hostCaret -ne $null) -and ([math]::Abs($hostCaret[0] - $exp[0]) -le 0.01) -and ([math]::Abs($hostCaret[1] - $exp[1]) -le 0.01)
          $nextLine = $true
          if ($cname -eq 'end') { $nextLine = ([math]::Abs($exp[1] - $lastLineRect[1]) -le 1.0) -and ([math]::Abs($exp[0] - $lastLineRect[0]) -le 1.0) }
          $selOk = $false; $rawSel = $null; $selText = '<none>'
          $sw2 = [Diagnostics.Stopwatch]::StartNew()
          while ($sw2.Elapsed.TotalSeconds -lt 4 -and -not $selOk) {
            $s2 = $tp.GetSelection()
            if ($s2 -ne $null -and $s2.Count -eq 1) { $selText = $s2[0].GetText(-1); $rawSel = Raw-Rects $s2[0] $cx $cy; $selOk = ($selText -ceq '') -and ($hostCaret -ne $null) -and (Test-CaretRect $rawSel $hostCaret 1.0) }
            if (-not $selOk) { Start-Sleep -Milliseconds 60 }
          }
          $cxInfo += "$cname@$cidx host_caret=$(if ($hostCaret -eq $null) { 'none' } else { Fmt-Rects @(,$hostCaret) }) uia_selection_raw=$(if ($rawSel -eq $null) { 'unavailable' } else { Fmt-Rects $rawSel }) client_range_raw=$(if ($rawDirect -eq $null) { 'unavailable' } else { Fmt-Rects $rawDirect })"
          if (-not ($okApply -and $selOk -and $hostIsExp -and $nextLine)) { $cxBad += "$cname@$cidx applied=$okApply uia_matches_host=$selOk host_is_expected=$hostIsExp on_last_line=$nextLine" }
        }
        Add-Check "B phase$p caret rectangles via Select(): blank line, paragraph start, end after the trailing newline (UIA selection rectangle = host caret)" (($cxBad.Count -eq 0) -and ($cxN -eq 3)) "carets_checked=$cxN bad=[$($cxBad -join ' ; ')] :: $($cxInfo -join ' ; ')"
        Add-Check "B phase$p app self-check (cells, newline cells, AX runs, lines partition the text)" (($selfLine -match 'pass=true') -and ($physLine -match 'pass=true')) "$selfLine | $physLine"

        if ($p -eq 5) {
          # a selection that crosses two paragraph breaks: text, global character indices and per-line rectangles
          $sp = $V.Selects['span']
          $before = (Read-Shared $logPath).Length
          (Range-At $tp $sp.a $sp.b $nch).Select()
          $applied = Wait-Tail $logPath $before "^SELRECT phase=$p anchor=$($sp.a) focus=$($sp.b) rects=" 8
          $okApply2 = ($applied -match "(?m)^ACTION setSelection node=3 anchor=$($sp.a) focus=$($sp.b)") -and ($applied -match "(?m)^APPLY select anchor=$($sp.a) focus=$($sp.b) phase=$p")
          $selTxt = Wait-SelText $tp $sp.text 4
          $hostSelR = Parse-Rects (([regex]::Match($applied, "(?m)^SELRECT phase=$p anchor=$($sp.a) focus=$($sp.b) rects=(.*?)\r?$")).Groups[1].Value)
          $hostSelNZ = @($hostSelR | Where-Object { $_[2] -gt 0.5 })
          $selR = $null
          $swr = [Diagnostics.Stopwatch]::StartNew(); $rectsOk = $false
          while ($swr.Elapsed.TotalSeconds -lt 4 -and -not $rectsOk) {
            $s3 = $tp.GetSelection()
            if ($s3 -ne $null -and $s3.Count -ge 1) { $selR = Uia-Rects $s3[0] $cx $cy; $rectsOk = ((Max-RectErr $selR $hostSelNZ) -le 1.0) }
            if (-not $rectsOk) { Start-Sleep -Milliseconds 60 }
          }
          Add-Check 'B selection across paragraph breaks via Select(): text, character indices and per-line rectangles' ($okApply2 -and ($selTxt -ceq $sp.text) -and $rectsOk) "applied=$okApply2 uia_selection_text='$(($selTxt -replace "`n",'\n'))' expected='$(($sp.text -replace "`n",'\n'))' uia_rects=$(Fmt-Rects $selR) host_rects_nonzero=$(Fmt-Rects $hostSelNZ)"
        }
      }

      Set-Content -Path (Join-Path $runDir "ack-$p.txt") -Value 'ack' -Encoding ascii
      Start-Sleep -Milliseconds 200
    }

    # ---- end of the run (host exits after the last ack)
    $done = Wait-Log $logPath '^HOSTSUMMARY ' 40
    $doneOk = ($done -match '(?m)^DONE phases=')
    if (-not $proc.WaitForExit(30000)) { try { $proc.Kill() } catch { } ; $info.killed = $true }
    $proc.WaitForExit()
    $info.exitCode = $proc.ExitCode
    Add-Check 'app ran all phases and shut down' ($doneOk -and ($proc.ExitCode -eq 0)) "DONE line present=$doneOk exit=$($proc.ExitCode)"
    $miss = @($cacheSeen.Keys | Where-Object { ($_ -le 2) -and ($cacheSeen[$_] -ne 'miss') }).Count
    $hit = @($cacheSeen.Keys | Where-Object { (($_ -eq 3) -or ($_ -eq 4)) -and ($cacheSeen[$_] -ne 'hit') }).Count
    Add-Check 'measurement cached (A: misses on the 3 new widths, hits on the 2 repeats)' (($miss -eq 0) -and ($hit -eq 0) -and ($cacheSeen.Count -ge 5)) ("cache per phase: " + (($cacheSeen.Keys | Sort-Object | ForEach-Object { "p$_=$($cacheSeen[$_])" }) -join ' '))
    Add-Check 'all measurements synchronous (UI thread, before commit)' (($commitLines.Count -eq $phaseCount) -and ($done -match 'HC PASS every phase measured, laid out and committed') -and ($done -match 'HC PASS no stale or unknown-node events') -and ($done -match 'HC PASS no thread violations')) "COMMIT lines=$($commitLines.Count)/$phaseCount (swr_measure_text is a synchronous UI-thread call; an off-thread call returns SWR_E_WRONG_THREAD and a commit follows each measure in the same turn)"
    $physOk = ($commitLines.Count -ge 1)
    foreach ($c in $commitLines) { if ([math]::Abs($c[0] - $c[1]) -gt 0.01) { $physOk = $false } }
    foreach ($ph in $physSeen) { if (-not $ph[1]) { $physOk = $false } }
    Add-Check 'physical-px commit (logical x scale_factor, per commit)' ($physOk -and $commitLines.Count -eq $phaseCount) (($commitLines | ForEach-Object { "w=$($_[2]) scale=$($_[3]) line0_phys=$($_[0]) expect=$($_[1])" }) -join '; ')
    $appDpi = $hostDpiSeen
    Add-Check 'DPI recorded and matches window scale' ([math]::Abs($appDpi - $info.dpi) -le 0.5) "GetDpiForWindow=$($info.dpi) host_dpi=$appDpi"
    $actN = ([regex]::Matches($done, '(?m)^ACTION setSelection')).Count
    Add-Check 'AccessKit action requests logged' ($actN -ge 8) "ACTION setSelection lines=$actN (expect 8: A alpha; B phase 5: blank, p2start, end, span; B phase 6: blank, p2start, end)"
    foreach ($hm in [regex]::Matches($done, '(?m)^HC (PASS|FAIL) (.*?) \[(.*)\]\r?$')) { Add-Check ('host: ' + $hm.Groups[2].Value) ($hm.Groups[1].Value -eq 'PASS') $hm.Groups[3].Value }
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
  # the run-4 text built from code points (this file is ASCII: Windows PowerShell 5.1 reads BOM-less files as ANSI)
  $jp = -join ([int[]](0x65E5, 0x672C, 0x8A9E, 0x306E, 0x30C6, 0x30AD, 0x30B9, 0x30C8) | ForEach-Object { [char]$_ })
  $kanji = -join ([int[]](0x6F22, 0x5B57) | ForEach-Object { [char]$_ })
  $smile = [char]::ConvertFromUtf32(0x1F642)
  $cpsA = Get-Cps ("Alpha beta $jp $smile gamma delta $kanji epsilon zeta $smile$smile eta theta iota kappa.")
  if ($cpsA.Count -ne 74) { $fails += "Get-Cps count $($cpsA.Count) != 74" }
  $stops = Word-Stops $cpsA
  if (($stops.Count - 1) -ne 23) { $fails += "Word-Stops moves $($stops.Count - 1) != 23 (22 interior starts + end of document)" }
  if ((Unesc 'a\nb\\c') -cne "a`nb\c") { $fails += 'Unesc' }
  $cpsB = Get-Cps "a b`n`nc`n"
  $stopsB = Word-Stops $cpsB
  if ((($stopsB -join ',') -ne '0,2,4,5,7')) { $fails += "Word-Stops with paragraph starts: $($stopsB -join ',') != 0,2,4,5,7" }
  $pr = Parse-Rects '1.50,2,3,4|5,6,7,8'
  if ($pr.Count -ne 2 -or $pr[1][2] -ne 7) { $fails += 'Parse-Rects' }
  if ((Max-RectErr $pr $pr) -ne 0) { $fails += 'Max-RectErr' }
  if (-not (Test-CaretRect @(,[double[]]@(10.0, 20.0, 0.0, 60.0)) ([double[]]@(10.5, 20.0, 2.5, 60.0)) 1.0)) { $fails += 'Test-CaretRect' }
  if ($script:RawGet -eq $null -or $script:RangeHandle -eq $null) { $fails += 'UIA raw rectangle reflection handles unavailable' }
  $edits = Test-ParseFile $PSCommandPath
  if ($edits.Count -ne 0) { $fails += "parse errors: $($edits.Count)" }
  foreach ($f in $fails) { Write-Output "DRYRUN FAIL $f" }
  Write-Output ("DRYRUN drive-textgeom logic " + $(if ($fails.Count -eq 0) { 'PASS' } else { 'FAIL' }) + " (word moves $($stops.Count - 1), code points $($cpsA.Count))")
  exit $(if ($fails.Count -eq 0) { 0 } else { 1 })
}

# ---------------------------------------------------------------- the N runs
New-Item -ItemType Directory -Force $OutDir | Out-Null
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $lines.Add($s) }
Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o) runs=$Runs"
Log (Get-Artifacts $Bin @('TextGeom06.exe'))
$results = @()
for ($n = 1; $n -le $Runs; $n++) {
  $r = Invoke-TextRun $n
  $results += $r
  Log ("RUN {0:D2} {1} checks={2}/{3} exit={4} ms={5}" -f $n, $(if ($r.Pass) { 'PASS' } else { 'FAIL' }), ($r.Total - $r.Failed.Count), $r.Total, $r.Info.exitCode, $r.Info.ms)
  foreach ($f in $r.Failed) { $d = [string]$f.detail; if ($d.Length -gt 700) { $d = $d.Substring(0, 700) + '...' }; Log ("  FAIL {0} [{1}]" -f $f.name, $d) }
  [System.IO.File]::WriteAllText($Result, [string]::Join("`r`n", $lines) + "`r`n", (New-Object System.Text.UTF8Encoding($false)))   # progress survives a killed task
  Start-Sleep -Milliseconds 1500
}
$pass = @($results | Where-Object { $_.Pass }).Count
Log ''
Log "--- run 01 checks (what is asserted) ---"
if ($results.Count -gt 0) { foreach ($c in $results[0].Checks) { $d = [string]$c.detail; if ($d.Length -gt 300) { $d = $d.Substring(0, 300) + '...' }; Log ("{0} {1} [{2}]" -f $c.status, $c.name, $d) } }
Log ''
Log ("SUMMARY runs={0} pass={1} fail={2} checks_per_run={3}" -f $Runs, $pass, ($Runs - $pass), $(if ($results.Count -gt 0) { $results[0].Total } else { 0 }))
Log "ROW6 TEXTGEOM $(if ($pass -eq $Runs) { 'PASS' } else { 'FAIL' }) ($pass/$Runs runs)"
Log "ended=$(Get-Date -Format o)"
[System.IO.File]::WriteAllText($Result, [string]::Join("`r`n", $lines) + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
