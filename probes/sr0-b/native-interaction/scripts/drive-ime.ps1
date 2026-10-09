# SR0 lane R9 (a): real Microsoft Japanese IME composition against the ABI 0.6 FreshOnBridge fixtures.
# Runs INSIDE an interactive desktop session (one-shot scheduled task, schedule-native.ps1). Not for SSH or a non-interactive shell.
#   -Fixture F7  core IME checks (marked text, conversion, commit, Escape, candidate window placement)
#   -Fixture F7live  F7 with a REAL composition and the exe's in-process release hook (--f7-live --release-event): the "insert row above"
#                    engine release is fired mid-composition without any input or UIA action (identity + marked-range survival)
#   -Fixture F8  identity under a structural change while a REAL composition is open (row removed above the composing row)
# The probe window's input is switched to the Japanese IME with window-targeted messages (no global hotkey). Romaji is
# typed only through the gated global SendInput path in native-common.ps1 (foreground lock, per-key re-check, abort).
# Observation: UIA ValuePattern/TextPattern live (the AX value is the DISPLAY text: committed text with the marked text
# inserted), and after exit the exe's EVT lines and its self-test ASSERT detail strings (the runtime text-store log).
param(
  [string]$Base = 'D:\Claude\sr0s-bridge06b',
  [ValidateSet('F7', 'F7live', 'F8')][string]$Fixture = 'F7',
  [string]$ReleaseEvent = 'Local\SR0_RELEASE_HOOK',
  [string]$Out = 'D:\Claude\sr0s-bridge06b\result-native-ime.txt',
  [Parameter(Mandatory)][string]$ExpectExe,
  [Parameter(Mandatory)][string]$ExpectDll
)
. "$PSScriptRoot\native-common.ps1"

$NI = U 0x306B; $HO = U 0x307B; $NN = U 0x3093
$NIPPON = (U 0x65E5) + (U 0x672C)          # the two CJK ideographs for "Japan"
$TIP_GUID = '{03B5835F-F03C-411B-9CE2-AA23E1171E36}'
$PROFILE_GUID = '{A76C93D9-5523-4E90-AAFA-4DB112F9AC76}'
$ready = "$Out.ready"
$script:Budget = $null
function Budget-Left { if ($script:Budget -eq $null) { return 999999 }; return (52000 - $script:Budget.ElapsedMilliseconds) }

Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) fixture=$Fixture started=$(Get-Date -Format o)"
if ((Get-Process -Id $PID).SessionId -eq 0) { Add-Check 'interactive-session' 'FAIL' 'session 0: not an interactive desktop'; Write-Result $Out "ime-$Fixture"; exit 3 }
if (-not (Verify-Tree $Base $ExpectExe $ExpectDll)) { Add-Check 'artifacts' 'FAIL' 'exe or renderer hash differs from the pinned tuple'; Write-Result $Out "ime-$Fixture"; exit 3 }

# ------------------------------------------------------------ (1) is the Japanese IME (0411 TIP) installed?
$regKey = "HKLM:\SOFTWARE\Microsoft\CTF\TIP\$TIP_GUID\LanguageProfile\0x00000411\$PROFILE_GUID"
$regOk = Test-Path $regKey
$userTips = @()
try { $userTips = @(Get-WinUserLanguageList | ForEach-Object { $_.InputMethodTips }) } catch { }
$wantTip = "0411:$TIP_GUID$PROFILE_GUID"
$userOk = ($userTips -contains $wantTip)
$jaHkls = [SRN.N]::JapaneseHkls()
Add-Check 'ime-installed' $(if ($regOk -and $userOk -and $jaHkls.Count -gt 0) { 'PASS' } else { 'FAIL' }) "tip_registered=$regOk user_has_tip=$userOk (want $wantTip) user_tips=[$($userTips -join ' ')] hkls_0411=[$(($jaHkls | ForEach-Object { '0x' + $_.ToString('X8') }) -join ',')]"
if (-not ($regOk -and $userOk -and $jaHkls.Count -gt 0)) { Write-Result $Out "ime-$Fixture"; exit 3 }
$hklJa = ($jaHkls | Sort-Object { ((($_ -shr 16) -band 0xFFFF) -eq 0xE001) } -Descending | Select-Object -First 1)

$exeFixture = if ($Fixture -eq 'F7live') { 'F7' } else { $Fixture }
$exeExtra = if ($Fixture -eq 'F7live') { "--f7-live --release-event `"$ReleaseEvent`"" } else { '' }
$script:Root = Start-Fixture $Base $exeFixture $ready $exeExtra
if ($script:Root -eq $null) { Add-Check 'window' 'FAIL' 'no probe window'; Close-And-Collect $Fixture; Write-Result $Out "ime-$Fixture"; exit 3 }
$procIdOut = [uint32]0
$tid = [SRN.N]::GetWindowThreadProcessId($script:Hwnd, [ref]$procIdOut)
$layoutBefore = [SRN.N]::LayoutOfThread($tid)
Log ("probe_thread=$tid layout_before=0x{0:X8} ja_hkl=0x{1:X8} input_struct_size=$([SRN.N]::InputSize())" -f $layoutBefore, $hklJa)

# ------------------------------------------------------------ IME control, window-targeted
function Ime-Readback {
  return [pscustomobject]@{ Open = [SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_GETOPENSTATUS, 0); Conv = [SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_GETCONVERSIONMODE, 0); Layout = [SRN.N]::LayoutOfThread($tid) }
}
function Switch-Japanese {
  # (a) the probe thread's keyboard layout/TIP: WM_INPUTLANGCHANGEREQUEST to the probe window (per window, not global)
  [void][SRN.N]::PostMessage($script:Hwnd, [SRN.N]::WM_INPUTLANGCHANGEREQUEST, [IntPtr]0, [IntPtr]$hklJa)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt 3000 -and (([SRN.N]::LayoutOfThread($tid) -band 0xFFFF) -ne 0x411)) { Start-Sleep -Milliseconds 100 }
  # (b) open status + hiragana conversion mode (IME_CMODE_NATIVE | IME_CMODE_FULLSHAPE = 0x9) on the probe thread via its
  #     default IME window: ImmSetOpenStatus / ImmSetConversionStatus need the owning thread's HIMC, so the equivalent
  #     WM_IME_CONTROL (IMC_SETOPENSTATUS / IMC_SETCONVERSIONMODE) is processed on that thread instead.
  $r1 = [SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_SETOPENSTATUS, 1)
  Start-Sleep -Milliseconds 200
  $r2 = [SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_SETCONVERSIONMODE, 9)
  Start-Sleep -Milliseconds 300
  $rb = Ime-Readback
  Log ("ime_switch set_open_rc=$r1 set_conv_rc=$r2 readback open=$($rb.Open) conv=0x{0:X} layout=0x{1:X8}" -f $rb.Conv, $rb.Layout)
  return $rb
}
function Restore-Ime {
  [void][SRN.N]::ImeControl($script:Hwnd, [SRN.N]::IMC_SETOPENSTATUS, 0)
  Start-Sleep -Milliseconds 150
  [void][SRN.N]::PostMessage($script:Hwnd, [SRN.N]::WM_INPUTLANGCHANGEREQUEST, [IntPtr]0, [IntPtr]$layoutBefore)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt 3000 -and [SRN.N]::LayoutOfThread($tid) -ne $layoutBefore) { Start-Sleep -Milliseconds 100 }
  $rb = Ime-Readback
  Log ("ime_restore open=$($rb.Open) layout=0x{0:X8} (before 0x{1:X8})" -f $rb.Layout, $layoutBefore)
  return ([SRN.N]::LayoutOfThread($tid) -eq $layoutBefore)
}

# ------------------------------------------------------------ observation helpers
function Marked-Of([string]$row, [string]$v0) {
  $v = Value-Of (Edit $row)
  if ($v.StartsWith($v0)) { return $v.Substring($v0.Length) }
  return "<divergent value=[$v]>"
}
# Type romaji one key at a time; after each key wait (<=1.5 s) for the display text to change, then record it.
function Type-And-Observe([string]$row, [string]$v0, [string]$romaji) {
  $seen = New-Object System.Collections.Generic.List[string]
  $prev = Marked-Of $row $v0
  foreach ($c in $romaji.ToUpper().ToCharArray()) {
    if (-not (Send-GatedKey ([uint16][int]$c) "romaji-$c" 120)) { break }
    $sw = [Diagnostics.Stopwatch]::StartNew(); $cur = $prev
    do { Start-Sleep -Milliseconds 100; $cur = Marked-Of $row $v0 } while ($cur -eq $prev -and $sw.ElapsedMilliseconds -lt 1500)
    $seen.Add($cur); $prev = $cur
  }
  return ,$seen.ToArray()
}
function Space-Until([string]$row, [string]$v0, [string]$want, [int]$max) {
  $seen = New-Object System.Collections.Generic.List[string]; $n = 0
  while ($n -lt $max) {
    $n++
    if (-not (Send-GatedKey 0x20 "space-$n" 120)) { break }
    Start-Sleep -Milliseconds 350
    $m = Marked-Of $row $v0; $seen.Add($m)
    if ($m -eq $want) { break }
  }
  return [pscustomobject]@{ Presses = $n; Seen = $seen.ToArray(); Reached = ($seen.Count -gt 0 -and $seen[$seen.Count - 1] -eq $want) }
}
function Esc-Until-Clear([string]$row, [string]$v0, [int]$max) {
  $n = 0; $m = Marked-Of $row $v0
  while ($m -ne '' -and $n -lt $max) {
    $n++
    if (-not (Send-GatedKey 0x1B "escape-$n" 120)) { break }
    Start-Sleep -Milliseconds 400; $m = Marked-Of $row $v0
  }
  return [pscustomobject]@{ Presses = $n; Marked = $m }
}

# Candidate window: located by class name among visible top-level windows other than the probe (Windows 11 candidate UI
# is a separate top-level window); ImmGetCandidateWindow cannot be used from this process (the HIMC belongs to the probe thread).
function Candidate-Windows($before) {
  $beforeSet = @{}; foreach ($w in $before) { $beforeSet[$w.Hwnd] = $true }
  $now = [SRN.N]::TopWindows(); $new = @(); $hit = @()
  foreach ($w in $now) {
    if (-not $w.Visible -or $w.Pid -eq $script:Proc.Id -or $w.Hwnd -eq $script:Hwnd.ToInt64()) { continue }
    $area = ($w.R - $w.L) * ($w.B - $w.T)
    if ($area -lt 400) { continue }
    if (-not $beforeSet.ContainsKey($w.Hwnd)) { $new += $w }
    if ($w.Cls -match 'Candidate' -or $w.Title -match 'Candidate') { $hit += $w }
  }
  return [pscustomobject]@{ New = $new; Hit = $hit }
}
function Measure-Candidate([string]$row, [string]$v0, $before) {
  Start-Sleep -Milliseconds 500
  $el = Edit $row
  $caret = Caret-Info $el
  $startRect = Char-Rect $el (Cp-Count $v0)
  $cw = Candidate-Windows $before
  $scale = [SRN.N]::GetDpiForWindow($script:Hwnd) / 96.0
  $cand = $cw.Hit | Sort-Object { ($_.R - $_.L) * ($_.B - $_.T) } | Select-Object -First 1
  Log ("candidate_probe caret_rect=$(Fmt-Rect $caret.CaretRect) comp_start_rect=$(Fmt-Rect $startRect) new_windows=[" + (($cw.New | ForEach-Object { "$($_.Cls)|$($_.Title)|$($_.L),$($_.T),$($_.R),$($_.B)" }) -join '; ') + "] class_hits=$(@($cw.Hit).Count) scale=$scale")
  $bounds = Last-CaretBounds
  Log "candidate_probe exe_caret_bounds_screen=$(Fmt-Rect $bounds)"
  return [pscustomobject]@{ Candidate = $cand; Caret = $caret; Start = $startRect; Bounds = $bounds; Scale = $scale; New = $cw.New }
}
function Eval-Anchor($m) {
  if ($m.Candidate -eq $null) { return $null }
  # reference = what the exe returned to the IME as the caret rectangle (storeCaretBounds, EVT ime/caret-bounds); the UIA
  # rectangle of the first composed character is the fallback for an exe that does not log bounds.
  $ref = if ($m.Bounds -ne $null) { $m.Bounds } else { $m.Start }
  if ($ref -eq $null) { return $null }
  $c = $m.Candidate; $s = $m.Scale
  $dx = $c.L - $ref[0]; $dy = $c.T - ($ref[1] + $ref[3])
  $ok = ([math]::Abs($dx) -le 60 * $s) -and ($dy -ge -20 * $s) -and ($dy -le 140 * $s)
  return [pscustomobject]@{ Ok = $ok; Dx = $dx; Dy = $dy }
}

# ============================================================ run
$committedKana = $null
$obs1 = @(); $obsC1 = $null
try {
  if ($Fixture -eq 'F7live') {
    # --- setup: "ka" through the gated VK path (IME still off), then NO programmatic composition: the exe waits for the hook
    [void](Focus-Edit 'Row 2')
    [void](Send-GatedKey 0x4B 'setup-k' 220); [void](Send-GatedKey 0x41 'setup-a' 220)
    [void](Wait-Value 'Row 2' 'Row 2ka' 20000)
    $armedSw = [Diagnostics.Stopwatch]::StartNew(); $armed = $false
    while (-not $armed -and -not $script:Proc.HasExited -and $armedSw.ElapsedMilliseconds -lt 20000) {
      $armed = @(Parse-Evt $script:StdTap.Snapshot() | Where-Object { $_.kind -eq 'hook' -and $_.payload.phase -eq 'armed' }).Count -gt 0
      if (-not $armed) { Start-Sleep -Milliseconds 100 }
    }
    Log "hook_armed=$armed waited_ms=$($armedSw.ElapsedMilliseconds)"
    $script:Budget = $null
    $row = 'Row 2'
    $v0 = Value-Of (Edit $row)
    Add-Check 'precondition-row2' $(if ($v0 -eq 'Row 2ka' -and $armed) { 'PASS' } else { 'FAIL' }) "value=[$v0] release hook armed (exe EVT hook/armed)=$armed (F7live: no programmatic composition ran)"
  } elseif ($Fixture -eq 'F7') {
    # --- setup exactly as scripts/drive-fixture.ps1 F7 (IME still off): "ka" through the gated VK path
    [void](Focus-Edit 'Row 2')
    [void](Send-GatedKey 0x4B 'setup-k' 220); [void](Send-GatedKey 0x41 'setup-a' 220)
    [void](Wait-Value 'Row 2' 'Row 2ka' 20000)
    [void](Wait-Element { Edit 'Row 99' } 'inserted row 99 (Engine 0)' 30000)
    [void](Wait-Value 'Row 2' 'Row 2kana' 20000)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path $ready) -and -not $script:Proc.HasExited -and $sw.ElapsedMilliseconds -lt 20000) { Start-Sleep -Milliseconds 100 }
    $script:Budget = [Diagnostics.Stopwatch]::StartNew()   # the exe closes itself 60 s after the ready file: stay inside 52 s
    Log "ready_file=$(Test-Path $ready) waited_ms=$($sw.ElapsedMilliseconds)"
    $row = 'Row 2'
    $v0 = Value-Of (Edit $row)
    Add-Check 'precondition-row2' $(if ($v0 -eq 'Row 2kana') { 'PASS' } else { 'FAIL' }) "value=[$v0] (after the exe's programmatic F7 script)"
  } else {
    # --- setup exactly as scripts/drive-fixture.ps1 F8 (up to focusing Row 3)
    [void](Invoke-El (Find-Named 'Insert above' ([System.Windows.Automation.ControlType]::Button) 15000) 'Insert above')
    [void](Wait-Element { Edit 'Row 101' } 'inserted row 101 (Toolbar 0)' 30000)
    Set-Value 'Row 3' 'AX value'; [void](Wait-Value 'Row 3' 'AX value')
    [void](Focus-Edit 'Row 3')
    Start-Sleep -Milliseconds 700
    $row = 'Row 7'
    $v0 = 'Row 7'
  }

  # ------------------------------------------------------------ (2) switch the probe's input to the Japanese IME
  $rb = Switch-Japanese
  $imeOn = (([SRN.N]::LayoutOfThread($tid) -band 0xFFFF) -eq 0x411) -and ($rb.Open -gt 0)
  if (-not $imeOn) {
    # Fallback that is still window-targeted: the IME-ON virtual key through the gated path (VK_IME_ON 0x16, then hiragana 0xF2).
    Log 'ime_switch fallback: VK_IME_ON and VK_DBE_HIRAGANA via the gated SendInput path'
    [void](Send-GatedKey 0x16 'vk-ime-on' 300); [void](Send-GatedKey 0xF2 'vk-hiragana' 300)
    $rb = Ime-Readback
    $imeOn = (([SRN.N]::LayoutOfThread($tid) -band 0xFFFF) -eq 0x411) -and ($rb.Open -gt 0)
  }
  Add-Check 'ime-activated-on-probe-thread' $(if ($imeOn) { 'PASS' } else { 'FAIL' }) ("layout=0x{0:X8} open_status=$($rb.Open) conversion_mode=0x{1:X} (hiragana = native|fullshape = 0x9)" -f $rb.Layout, $rb.Conv)
  if (-not $imeOn) { throw 'ime-not-active' }
  Add-Check 'ime-hiragana-mode' $(if ($rb.Conv -ge 0 -and ($rb.Conv -band 0x9) -eq 0x9) { 'PASS' } else { 'FAIL' }) ("conversion_mode=0x{0:X}" -f $rb.Conv)
  Log "imm_context_from_driver_process=$([SRN.N]::ProbeImmContext($script:Hwnd)) (0 expected: an HIMC cannot be taken across processes, so ImmGetCandidateWindow is not callable from here)"

  if ($Fixture -eq 'F8') { [void](Focus-Edit 'Row 7'); Start-Sleep -Milliseconds 500; $v0 = Value-Of (Edit $row) }

  # ------------------------------------------------------------ composition 1: "nihonn" -> marked text tracks composition
  $winBefore = [SRN.N]::TopWindows()
  $idxBefore = [array]::IndexOf((Edit-Names), $row)
  $obs1 = Type-And-Observe $row $v0 'nihonn'
  $expect1 = @('n', $NI, ($NI + 'h'), ($NI + $HO), ($NI + $HO + 'n'), ($NI + $HO + $NN))
  $norm1 = @($obs1 | ForEach-Object { Norm-Width $_ })
  $trackOk = ($norm1.Count -eq $expect1.Count)
  if ($trackOk) { for ($i = 0; $i -lt $expect1.Count; $i++) { if ($norm1[$i] -ne $expect1[$i]) { $trackOk = $false } } }
  Add-Check 'marked-text-tracks-composition' $(if ($trackOk) { 'PASS' } else { 'FAIL' }) ("display minus committed prefix after each key n,i,h,o,n,n: observed=[" + ($obs1 -join ' | ') + "] expected(width-normalised)=[" + ($expect1 -join ' | ') + "]")

  if ($Fixture -eq 'F7live') {
    # ---------------------------------------------------------- real-IME insert-above: the engine release fires mid-composition
    $uuid2 = Row-Uuid (Edit $row)
    $focusBefore = Focused-Name
    $dispBefore = Value-Of (Edit $row)
    $sigOk = Signal-Release $ReleaseEvent
    $ins = Wait-Element { Edit 'Row 99' } 'inserted row 99 (Engine 0)' 12000
    $script:Budget = [Diagnostics.Stopwatch]::StartNew()   # the exe script is now at awaitClose: its 60 s limit starts here
    Start-Sleep -Milliseconds 800
    $e2 = Edit $row
    $idxAfter = [array]::IndexOf((Edit-Names), $row)
    $uuid2After = Row-Uuid $e2
    $dispAfter = Value-Of $e2
    $focusAfter = Focused-Name
    $markedAfter = Marked-Of $row $v0
    $hookEvt = @(Parse-Evt $script:StdTap.Snapshot() | Where-Object { $_.kind -eq 'hook' -and $_.payload.phase -eq 'release' }) | Select-Object -First 1
    Add-Check 'insert-above-fires-mid-real-composition' $(if ($sigOk -and $ins -ne $null -and $hookEvt -ne $null -and $hookEvt.payload.key -eq 'insert-above' -and $hookEvt.payload.marked -ne 'none') { 'PASS' } else { 'FAIL' }) "signalled=$sigOk row99_present=$($ins -ne $null) hook EVT key=$($hookEvt.payload.key) marked_at_release=$($hookEvt.payload.marked) display_at_release=[$($hookEvt.payload.display)] committed_at_release=[$($hookEvt.payload.committed)] (a composition must be open at the release)"
    Add-Check 'identity-and-composition-survive-insert-above-real-ime' $(if ($uuid2After -eq $uuid2 -and $idxAfter -eq ($idxBefore + 1) -and $dispAfter -eq $dispBefore -and $markedAfter -ne '' -and $focusAfter -eq $row) { 'PASS' } else { 'FAIL' }) "row inserted ABOVE the composing row during a REAL composition: uuid_before=$uuid2 uuid_after=$uuid2After index $idxBefore->$idxAfter (expect +1) display_before=[$dispBefore] display_after=[$dispAfter] marked_after=[$markedAfter] (non-empty expected) focus_before=$focusBefore focus_after=$focusAfter"
  }

  if ($Fixture -eq 'F8') {
    # ---------------------------------------------------------- identity: remove a row ABOVE the composing row mid-composition
    $uuid7 = Row-Uuid (Edit $row); $uuid6 = Row-Uuid (Edit 'Row 6')
    $focusBefore = Focused-Name
    $delBtn = Find-Id "row/$uuid6/delete" 8000
    Log "structural: composing=$row uuid=$uuid7 index_before=$idxBefore delete_target=Row 6 uuid=$uuid6 button_found=$($delBtn -ne $null)"
    $invoked = Invoke-El $delBtn 'Delete (row 6) mid-composition'
    $gone = Wait-Element { if ((Edit 'Row 6') -eq $null) { 'gone' } else { $null } } 'Row 6 removed' 8000
    $script:Budget = [Diagnostics.Stopwatch]::StartNew()   # the F8 script is now at awaitClose: 60 s limit starts here
    Start-Sleep -Milliseconds 800
    $e7 = Edit $row
    $idxAfter = [array]::IndexOf((Edit-Names), $row)
    $uuid7After = Row-Uuid $e7
    $valAfter = Value-Of $e7
    $focusAfter = Focused-Name
    Add-Check 'identity-survives-structural-change-mid-composition' $(if ($invoked -and $gone -and $uuid7After -eq $uuid7 -and $idxAfter -eq ($idxBefore - 1) -and $valAfter -eq ($v0 + $NI + $HO + $NN) -and $focusAfter -eq $row) { 'PASS' } else { 'FAIL' }) "row removed above composing row during a REAL composition: invoked=$invoked gone=$gone uuid_before=$uuid7 uuid_after=$uuid7After index $idxBefore->$idxAfter (expect -1) display_after=[$valAfter] expected=[$($v0 + $NI + $HO + $NN)] focus_before=$focusBefore focus_after=$focusAfter"
  }

  # ------------------------------------------------------------ conversion (Space) and candidate window
  $sp = Space-Until $row $v0 $NIPPON 4
  Add-Check 'conversion-to-nihon' $(if ($sp.Reached) { 'PASS' } else { 'FAIL' }) "Space presses=$($sp.Presses) marked after each press=[$($sp.Seen -join ' | ')] (target = the two ideographs for Japan; candidate order depends on the user's IME history, up to 4 presses allowed)"
  $m1 = Measure-Candidate $row $v0 $winBefore
  $a1 = Eval-Anchor $m1

  # ------------------------------------------------------------ commit (Enter) and UTF-16 selection
  if (Budget-Left -gt 6000) {
    [void](Send-GatedKey 0x0D 'enter-commit' 120); Start-Sleep -Milliseconds 700
    $e = Edit $row; $vC = Value-Of $e; $ci = Caret-Info $e
    $wantC = $v0 + $NIPPON
    $okC = ($vC -eq $wantC) -and ($ci.SelCount -eq 1) -and ($ci.SelLen16 -eq 0) -and ($ci.SelStart16 -eq $wantC.Length)
    Add-Check 'commit-replaces-marked-range-utf16-selection' $(if ($okC) { 'PASS' } else { 'FAIL' }) "value=[$vC] expected=[$wantC] selection start16=$($ci.SelStart16) len16=$($ci.SelLen16) (expected start16=$($wantC.Length), len 0; BMP-only text: supplementary-plane mapping is not exercised here) doc_equals_value=$($ci.Doc -eq $vC) err=$($ci.Err)"
  } else { Add-Check 'commit-replaces-marked-range-utf16-selection' 'NOT-RUN' 'budget exhausted' }

  # ------------------------------------------------------------ composition 2 after the commit: candidate window follows the caret
  if (Budget-Left -gt 14000) {
    $v1 = Value-Of (Edit $row)
    $winBefore2 = [SRN.N]::TopWindows()
    [void](Type-And-Observe $row $v1 'nihonn')
    $sp2 = Space-Until $row $v1 $NIPPON 1
    $m2 = Measure-Candidate $row $v1 $winBefore2
    $a2 = Eval-Anchor $m2
    if ($m1.Candidate -eq $null -or $m2.Candidate -eq $null) {
      $newDesc = ((@($m1.New) + @($m2.New)) | ForEach-Object { "$($_.Cls)|$($_.Title)|$($_.L),$($_.T),$($_.R),$($_.B)" }) -join '; '
      Add-Check 'candidate-window-anchored-to-caret' 'FAIL' "no visible top-level window with a class or title containing 'Candidate' was found after Space (comp1 found=$($m1.Candidate -ne $null) comp2 found=$($m2.Candidate -ne $null)); exe-logged caret bounds comp1=$(Fmt-Rect $m1.Bounds) comp2=$(Fmt-Rect $m2.Bounds) (screen px) so the expected anchor is known but the IME's window was not located; windows new after Space: [$newDesc]"
    } elseif ($a1 -eq $null -or $a2 -eq $null) {
      Add-Check 'candidate-window-anchored-to-caret' 'FAIL' "candidate window found (comp1 $($m1.Candidate.L),$($m1.Candidate.T); comp2 $($m2.Candidate.L),$($m2.Candidate.T)) but neither the exe-logged caret bounds (comp1=$(Fmt-Rect $m1.Bounds) comp2=$(Fmt-Rect $m2.Bounds)) nor the UIA rectangle (comp1=$(Fmt-Rect $m1.Start) comp2=$(Fmt-Rect $m2.Start)) was available, so anchoring cannot be judged"
    } else {
      $shiftCand = $m2.Candidate.L - $m1.Candidate.L
      $r1 = if ($m1.Bounds -ne $null -and $m2.Bounds -ne $null) { $m1.Bounds } else { $m1.Start }; $r2 = if ($m1.Bounds -ne $null -and $m2.Bounds -ne $null) { $m2.Bounds } else { $m2.Start }
      $shiftComp = $r2[0] - $r1[0]
      $shiftOk = ([math]::Abs($shiftCand - $shiftComp) -le 12 * $m1.Scale) -and ($shiftComp -gt 10 * $m1.Scale)
      Add-Check 'candidate-window-anchored-to-caret' $(if ($a1.Ok -and $a2.Ok) { 'PASS' } else { 'FAIL' }) ("candidate left/top vs composition start (screen px): comp1 cand=$($m1.Candidate.L),$($m1.Candidate.T) class=$($m1.Candidate.Cls) dx=$([math]::Round($a1.Dx)) dy_below_caret=$([math]::Round($a1.Dy)); comp2 cand=$($m2.Candidate.L),$($m2.Candidate.T) dx=$([math]::Round($a2.Dx)) dy=$([math]::Round($a2.Dy)); tolerance dx<=60*scale, dy in [-20,140]*scale, scale=$($m1.Scale)")
      Add-Check 'candidate-window-follows-caret-after-commit' $(if ($shiftOk) { 'PASS' } else { 'FAIL' }) "composition start moved by $([math]::Round($shiftComp)) px after the commit; candidate window moved by $([math]::Round($shiftCand)) px (tolerance 12*scale, and the caret must have moved > 10*scale)"
    }
    # --- Escape: back out of conversion, then out of the composition
    $esc = Esc-Until-Clear $row $v1 4
    $e = Edit $row; $vE = Value-Of $e; $ci = Caret-Info $e
    Add-Check 'escape-cancel-clears-composition' $(if ($esc.Marked -eq '' -and $vE -eq $v1 -and $ci.SelStart16 -eq $v1.Length) { 'PASS' } else { 'FAIL' }) "Escape presses=$($esc.Presses) marked_after=[$($esc.Marked)] value=[$vE] expected committed=[$v1] caret start16=$($ci.SelStart16) (expected $($v1.Length)); first Escape may only leave conversion mode"
    # --- pure cancel: unconverted composition then one Escape
    if (Budget-Left -gt 6000) {
      [void](Type-And-Observe $row $v1 'nihonn')
      $esc2 = Esc-Until-Clear $row $v1 2
      Add-Check 'escape-cancel-unconverted-composition' $(if ($esc2.Marked -eq '' -and $esc2.Presses -eq 1) { 'PASS' } else { 'FAIL' }) "unconverted composition, Escape presses=$($esc2.Presses) marked_after=[$($esc2.Marked)] (one press expected)"
    }
  } else {
    foreach ($id in @('candidate-window-anchored-to-caret', 'candidate-window-follows-caret-after-commit', 'escape-cancel-clears-composition')) { Add-Check $id 'NOT-RUN' 'budget exhausted before the second composition (the exe closes itself 60 s after its script ends)' }
  }

  # ------------------------------------------------------------ leave the fixture in its scripted end state
  if ($Fixture -eq 'F7') { Set-Value $row 'Row 2kana' } elseif ($Fixture -eq 'F8') { [void](Focus-Edit 'Row 3') }
}
catch { Log "driver_exception: $($_.Exception.Message)"; Add-Check 'driver-run' 'FAIL' "exception: $($_.Exception.Message)" }
finally {
  $restored = Restore-Ime
  Add-Check 'ime-restored' $(if ($restored) { 'PASS' } else { 'FAIL' }) "probe thread layout back to 0x$($layoutBefore.ToString('X8')) and IME closed"
  Close-And-Collect $Fixture
}

# ============================================================ post-hoc: the exe's own record (stdout, read after exit)
$std = $script:StdTap.Snapshot()
$evt = Parse-Evt $std
$asserts = @($std | Where-Object { $_ -match '^ASSERT \S+ \S+: (PASS|FAIL)' })
$verdict = ($std | Where-Object { $_ -like 'SELFTEST *' } | Select-Object -First 1)
Log "selftest_verdict=[$verdict]"
$failedAsserts = @($asserts | ForEach-Object { if ($_ -match '^ASSERT \S+ (\S+): FAIL') { $Matches[1] } })
# caret bounds the exe returned to the IME (EVT ime/caret-bounds): the evidence the candidate window can be checked against
$cbAll = @($evt | Where-Object { $_.kind -eq 'ime' -and $_.node_id -eq 'caret-bounds' })
$cbOk = @($cbAll | Where-Object { $_.payload.h -gt 0 -and $_.payload.w -gt 0 })
$cbX = @($cbOk | ForEach-Object { [math]::Round($_.payload.x) } | Sort-Object -Unique)
Add-Check 'ime-caret-bounds-logged' $(if ($cbOk.Count -ge 2 -and $cbX.Count -ge 2) { 'PASS' } else { 'FAIL' }) "exe EVT ime/caret-bounds lines=$($cbAll.Count) with a non-empty rectangle=$($cbOk.Count) distinct x positions=$($cbX.Count) (expected >=2: the caret rectangle must move as the composition grows) last=$(if ($cbOk.Count) { $l = $cbOk[$cbOk.Count - 1].payload; "x=$($l.x) y=$($l.y) w=$($l.w) h=$($l.h) scale=$($l.scale)" } else { 'none' })"
if ($Fixture -eq 'F7live') {
  $failedOther = @($failedAsserts)
  Add-Check 'f7live-selftest-verdict' $(if ($verdict -like '*: PASS*') { 'PASS' } else { 'FAIL' }) "failed asserts=[$($failedOther -join ',')] verdict=[$verdict] (live variant: insert-committed, identity-index-shift, no-teardown, release-hook-fired)"
  $row2 = $evt | Where-Object { $_.kind -eq 'hook' -and $_.payload.phase -eq 'release' } | Select-Object -First 1
  Add-Check 'f7live-hook-evidence-recorded' $(if ($row2 -ne $null -and $row2.payload.marked -ne 'none') { 'PASS' } else { 'FAIL' }) "release hook EVT: key=$($row2.payload.key) source=$($row2.payload.source) display=[$($row2.payload.display)] marked=$($row2.payload.marked)"
} elseif ($Fixture -eq 'F7') {
  # the exact-list asserts compare against the programmatic calls only; real IME input legitimately adds calls
  $allowed = @('text-store-keystrokes', 'ime-calls-recorded')
  $unexpected = @($failedAsserts | Where-Object { $allowed -notcontains $_ })
  Add-Check 'f7-selftest-programmatic-asserts-unaffected' $(if ($unexpected.Count -eq 0) { 'PASS' } else { 'FAIL' }) "failed asserts=[$($failedAsserts -join ',')] (expected to fail only: $($allowed -join ',') because the real IME added calls) unexpected=[$($unexpected -join ',')]"
  # runtime text-store log: imeCalls and replace calls from the exe's own ASSERT detail strings
  $callsLine = $asserts | Where-Object { $_ -match ' ime-calls-recorded: ' } | Select-Object -First 1
  $keysLine = $asserts | Where-Object { $_ -match ' text-store-keystrokes: ' } | Select-Object -First 1
  $calls = @(); if ($callsLine -match 'calls=(.*)$') { $calls = @($Matches[1] -split ',') }
  $keys = @(); if ($keysLine -match 'replace calls=(.*)$') { $keys = @($Matches[1] -split ',') }
  $real = @($calls | Select-Object -Skip 3)
  $want = @($obs1 | Where-Object { $_ -ne '' } | ForEach-Object { "mark:$_" })
  # every distinct marked string observed live in composition 1 must appear, in order, in the runtime's replaceAndMark log
  $pos = 0; $missing = @()
  foreach ($w in $want) { $found = $false; for ($i = $pos; $i -lt $real.Count; $i++) { if ($real[$i] -eq $w) { $pos = $i + 1; $found = $true; break } }; if (-not $found) { $missing += $w } }
  Add-Check 'runtime-text-store-log-matches-live-composition' $(if ($want.Count -gt 0 -and $missing.Count -eq 0 -and ($keys -contains $NIPPON)) { 'PASS' } else { 'FAIL' }) "runtime replaceAndMark/unmark calls after the 3 programmatic ones=[$($real -join ' ')] ; live-observed marks missing from it=[$($missing -join ' ')] ; replace calls=[$($keys -join ' ')] (commit must appear as the ideographs)"
  # model state from EVT: Row 2 uuid is in the field automation id; edits after the programmatic Row 2kana
  $edits = @($evt | Where-Object { $_.kind -eq 'state' -and $_.payload.op -eq 'edit' -and $_.payload.text -like 'Row 2*' })
  $texts = @($edits | ForEach-Object { $_.payload.text })
  $firstIdx = [array]::IndexOf($texts, 'Row 2kana')
  $afterFirst = @($texts | Select-Object -Skip ($firstIdx + 1))
  $wantEdits = @(($v0 + $NIPPON), 'Row 2kana')
  Add-Check 'model-state-edits-during-real-ime' $(if ($afterFirst.Count -eq 2 -and $afterFirst[0] -eq $wantEdits[0] -and $afterFirst[1] -eq $wantEdits[1]) { 'PASS' } else { 'FAIL' }) "state-edit texts for Row 2 after the programmatic stage=[$($afterFirst -join ' | ')] expected exactly [$($wantEdits -join ' | ')]: no model write while composing or on Escape; one write at commit; one write from the driver's restore"
  $emptyReplaces = @($evt | Where-Object { $_.kind -eq 'input' -and $_.payload.op -eq 'text-store-replace' -and $_.payload.inserted -eq '' }).Count
  Add-Check 'escape-visible-in-runtime-log' $(if ($emptyReplaces -ge 1) { 'PASS' } else { 'FAIL' }) "text-store-replace calls with empty text (the IME's cancel path)=$emptyReplaces (>=1 expected)"
} else {
  Add-Check 'f8-selftest-verdict' $(if ($verdict -like '*: PASS*') { 'PASS' } else { 'FAIL' }) "failed asserts=[$($failedAsserts -join ',')] verdict=[$verdict] (the real composition must not disturb the F8 script: Row 6 removed once, Row 3 focus and value kept)"
  $u7 = $uuid7
  $closedSeq = (@($evt | Where-Object { $_.node_id -eq 'window' -and $_.payload.phase -eq 'closed' }) | Select-Object -First 1).seq
  if ($closedSeq -eq $null) { $closedSeq = 99999999 }
  $dis = @($evt | Where-Object { $_.node_id -eq $u7 -and $_.payload.phase -eq 'disappear' -and $_.seq -lt $closedSeq }).Count
  $ed7 = @($evt | Where-Object { $_.node_id -eq $u7 -and $_.kind -eq 'state' -and $_.payload.op -eq 'edit' } | ForEach-Object { $_.payload.text })
  Add-Check 'identity-model-state-row7' $(if ($dis -eq 0 -and $ed7.Count -eq 1 -and $ed7[0] -eq ($v0 + $NIPPON)) { 'PASS' } else { 'FAIL' }) "Row 7 uuid=$u7 disappear events before window close=$dis (0 expected) state-edit texts=[$($ed7 -join ' | ')] (one edit at commit expected: marked text never reached the model before it)"
}
Write-Result $Out "ime-$Fixture"
