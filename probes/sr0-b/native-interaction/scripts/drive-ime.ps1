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

# ------------------------------------------------------------ exe-side candidate evidence (stderr `ime_cand` lines)
# The exe logs one line per IMN_OPENCANDIDATE / IMN_CHANGECANDIDATE:
#   ime_cand event=open|change got=.. form_style=.. form_pt=x,y form_rc=.. cand_windows=[class@l,t,r,b;...] caret=l,t,w,h|none
# (cand_windows = visible windows of our process, the default IME window, and visible classes containing IME/Candidate; screen px;
#  caret = the caret rect the exe returns to the IME, screen px; form_pt/form_rc are CLIENT px as the IME holds them.)
$script:CandOpenSeen = 0; $script:CandShots = 0; $script:CompStartIdx = 0
$script:CandHits = @()   # live WindowFromPoint hits taken at each ime_cand open (see Cand-Hit-Probe); Seq = open-line count when taken
$script:LayoutDone = @{} # raw exe-stderr line indices of ime_replace reason=layout lines already handled (see Layout-Trigger)
$script:LayoutRes = @()  # per layout move: client->screen old/new caret, and the candidate hits taken 400 ms after the move
# Newest `ime_cand event=open` line (from index $from) that has a caret, read from the RAW line. The parsed Caret field of
# Parse-ImeCand was observed flattened in the F8 log (caret=... repeated), so the probes use this instead.
function Open-Caret-Latest([int]$from = 0) {
  $c = $null; $all = Exe-ErrLines
  for ($i = $from; $i -lt $all.Count; $i++) {
    if ([string]$all[$i] -match 'ime_cand event=open .*caret=(-?\d+),(-?\d+),(-?\d+),(-?\d+)\s*$') { $c = [int[]]@([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4]) }
  }
  if ($null -eq $c) { return $null }
  return ,$c
}
function Exe-ErrLines { try { return @($script:ErrTap.Snapshot()) } catch { return @() } }
function Parse-ImeCand([int]$from = 0) {
  $o = @(); $all = Exe-ErrLines
  for ($i = $from; $i -lt $all.Count; $i++) {
    $l = [string]$all[$i]
    if ($l -notmatch 'ime_cand event=(open|change) got=(-?\d+) form_style=(\d+) form_pt=(-?\d+),(-?\d+) form_rc=(-?\d+),(-?\d+),(-?\d+),(-?\d+) cand_windows=\[(.*?)\] caret=(\S+)') { continue }
    $m = $Matches; $wins = @()
    foreach ($e in ($m[10] -split ';')) { if ($e -match '^(.*)@(-?\d+),(-?\d+),(-?\d+),(-?\d+)$') { $wins += [pscustomobject]@{ Cls = $Matches[1]; L = [int]$Matches[2]; T = [int]$Matches[3]; R = [int]$Matches[4]; B = [int]$Matches[5] } } }
    $car = $null; if ($m[11] -match '^(-?\d+),(-?\d+),(-?\d+),(-?\d+)$') { $car = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4]) }
    $o += [pscustomobject]@{ Event = $m[1]; Got = [int]$m[2]; Style = [int]$m[3]; Px = [int]$m[4]; Py = [int]$m[5]; Wins = $wins; Caret = $car; Raw = $l }
  }
  return ,$o
}
# Candidate UI windows = IME/Candidate-class windows with a real area (our own windows are listed by the exe but are not candidate UI).
function Cand-UiWins($e) { return @($e.Wins | Where-Object { $_.Cls -match '(?i)ime|candidate' -and (($_.R - $_.L) * ($_.B - $_.T)) -ge 400 }) }
function Anchored-To([int[]]$car, $w, [double]$s) {
  $caretX = $car[0]; $caretTop = $car[1]; $caretBottom = $car[1] + $car[3]
  $dx = $w.L - $caretX; $dyBelow = $w.T - $caretBottom; $dyAbove = $w.B - $caretTop
  $yOk = ([math]::Abs($dyBelow) -le 40 * $s) -or ([math]::Abs($dyAbove) -le 40 * $s)
  $xOk = ([math]::Abs($dx) -le 60 * $s) -or (($caretX -ge $w.L - 60 * $s) -and ($caretX -le $w.R + 60 * $s))
  return [pscustomobject]@{ Ok = ($yOk -and $xOk); Dx = $dx; Dy = $dyBelow; DyAbove = $dyAbove; Placement = $(if ([math]::Abs($dyBelow) -le 40 * $s) { 'below' } elseif ([math]::Abs($dyAbove) -le 40 * $s) { 'above' } else { 'neither' }); XOk = $xOk }
}
# Screenshot as soon as the exe reports IMN_OPENCANDIDATE (called from the typing / Space wait loops); at most 4 per run.
function Cand-Trigger {
  Layout-Trigger
  $n = @(Exe-ErrLines | Where-Object { $_ -match 'ime_cand event=open' }).Count
  if ($n -gt $script:CandOpenSeen) {
    $script:CandOpenSeen = $n
    Cand-Hit-Probe $n
    if ($script:CandShots -lt 4) { $script:CandShots++; Log "ime_cand_open_trigger n=$n shot=$($script:CandShots)"; Capture-Evidence "open$n" }
  }
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
  $script:CompStartIdx = (Exe-ErrLines).Count
  $prev = Marked-Of $row $v0
  foreach ($c in $romaji.ToUpper().ToCharArray()) {
    if (-not (Send-GatedKey ([uint16][int]$c) "romaji-$c" 120)) { break }
    $sw = [Diagnostics.Stopwatch]::StartNew(); $cur = $prev
    do { Start-Sleep -Milliseconds 100; Cand-Trigger; $cur = Marked-Of $row $v0 } while ($cur -eq $prev -and $sw.ElapsedMilliseconds -lt 1500)
    $seen.Add($cur); $prev = $cur
  }
  return ,$seen.ToArray()
}
function Space-Until([string]$row, [string]$v0, [string]$want, [int]$max, $winBase = $null) {
  $seen = New-Object System.Collections.Generic.List[string]; $n = 0; $script:CandSeen = $null
  while ($n -lt $max) {
    $n++
    if (-not (Send-GatedKey 0x20 "space-$n" 120)) { break }
    Start-Sleep -Milliseconds 350
    Cand-Trigger
    $m = Marked-Of $row $v0; $seen.Add($m)
    if ($winBase -ne $null) { Capture-Evidence "space$n-t350"; Start-Sleep -Milliseconds 850; Capture-Evidence "space$n-t1200" }
    if ($winBase -ne $null) { $cs = Candidate-Windows $winBase; $h = $cs.Hit | Select-Object -First 1; if ($h -ne $null) { $script:CandSeen = $h } }
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

# Candidate window detection (rewritten). The modern Microsoft IME (Windows 11, TSF) draws its candidate list in a popup that is
# frequently not "new" (a hidden window reused, shown on demand), not owned by the probe, and not titled "Candidate"; it may be hosted by
# TextInputHost / ctfmon / ImeBroker or live in the probe's own process (classes IME / MSCTFIME UI). So: snapshot EVERY top-level window
# (class, process, visible, rect) before the first Space and again after each Space; accept an IME-related window that is visible and
# (new | became visible | moved/resized | class says Candidate). If EnumWindows finds none, fall back to UI Automation: a List / candidate
# element under any IME-related top-level window (ImmGetCandidateWindow cannot be used: the HIMC belongs to the probe thread).
$script:PnCache = @{}
function Proc-Name([uint32]$procId) {
  if (-not $script:PnCache.ContainsKey($procId)) { $n = '?'; try { $n = (Get-Process -Id $procId -ErrorAction Stop).ProcessName } catch { }; $script:PnCache[$procId] = $n }
  return $script:PnCache[$procId]
}
$script:ImeClassRx = 'Candidate|^IME$|MSCTFIME|CiceroUI|Microsoft\.IME|ImeUI|IMEUI|IME\.|TextInput|InputHost|TF_|Ime'
$script:ImeProcRx = '^(TextInputHost|ctfmon|ImeBroker|InputApp|ChsIME|MicrosoftIME.*|imejp.*|IMEJP.*|IMJP.*)$'
function Win-Key($w) { return "$($w.Hwnd)" }
function Snap-Windows {
  $o = @()
  foreach ($w in [SRN.N]::TopWindows()) {
    # L..B = visible (DWM extended frame) rect; RawL..RawB = GetWindowRect, which includes the invisible resize/shadow border.
    $o += [pscustomobject]@{ Hwnd = $w.Hwnd; Pid = $w.Pid; Proc = (Proc-Name $w.Pid); Cls = $w.Cls; Title = $w.Title; L = $w.VL; T = $w.VT; R = $w.VR; B = $w.VB; RawL = $w.L; RawT = $w.T; RawR = $w.R; RawB = $w.B; VisFallback = $w.VisFallback; Visible = $w.Visible; Ex = $w.ExStyle }
  }
  return ,$o
}
function Is-ImeWin($w) { return ($w.Cls -match $script:ImeClassRx) -or ($w.Title -match 'Candidate|IME|Text Input') -or ($w.Proc -match $script:ImeProcRx) }
function Fmt-Win($w) {
  # Titles of windows that are neither ours nor IME-related (user documents, browser tabs) are never logged.
  $ours = ($script:Hwnd -ne $null -and $w.Hwnd -eq $script:Hwnd.ToInt64()) -or ($w.Title -match '^SwiftRight')
  $title = if ($ours -or (Is-ImeWin $w)) { $w.Title } else { '<redacted>' }
  $rects = "visible_rect=$($w.L),$($w.T),$($w.R),$($w.B)"
  if ($w.RawL -ne $null) { $rects += " raw_rect=$($w.RawL),$($w.RawT),$($w.RawR),$($w.RawB) dwm=$(if ($w.VisFallback) { 'fallback' } else { 'ok' })" }
  return "$($w.Proc)/$($w.Pid)|$($w.Cls)|$title|vis=$($w.Visible)|$rects|ex=0x$('{0:X}' -f $w.Ex)"
}

function Candidate-Windows($before) {
  $bset = @{}; foreach ($w in $before) { $bset[(Win-Key $w)] = $w }
  $now = Snap-Windows; $changed = @(); $ime = @(); $hit = @()
  foreach ($w in $now) {
    if ($w.Hwnd -eq $script:Hwnd.ToInt64()) { continue }
    $b = $bset[(Win-Key $w)]; $why = @()
    if ($b -eq $null) { $why += 'new' }
    else {
      if ($w.Visible -and -not $b.Visible) { $why += 'became-visible' }
      if ($w.Visible -and ($b.L -ne $w.L -or $b.T -ne $w.T -or $b.R -ne $w.R -or $b.B -ne $w.B)) { $why += 'rect-changed' }
    }
    $w | Add-Member -NotePropertyName Why -NotePropertyValue ($why -join '+') -Force
    $imeRel = Is-ImeWin $w
    if ($why.Count -gt 0 -and ($w.Visible -or $b -ne $null)) { $changed += $w }
    if ($imeRel) { $ime += $w }
    $area = ($w.R - $w.L) * ($w.B - $w.T)
    if ($w.Visible -and $area -ge 400 -and $imeRel -and ($why.Count -gt 0 -or $w.Cls -match 'Candidate' -or $w.Title -match 'Candidate')) { $hit += $w }
  }
  return [pscustomobject]@{ New = $changed; Ime = $ime; Hit = $hit }
}
# UIA fallback: IME-related top-level elements (by process or class), then List / candidate-named descendants with a real rectangle.
function Candidate-Uia {
  $res = @(); $diag = @()
  try {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $tops = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    $listCond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::List)
    foreach ($t in $tops) {
      $c = $null; try { $c = $t.Current } catch { continue }
      $pn = Proc-Name ([uint32]$c.ProcessId)
      if (-not (($pn -match $script:ImeProcRx) -or ($c.ClassName -match $script:ImeClassRx) -or ($c.Name -match 'Candidate|Text Input'))) { continue }
      $diag += "$pn|$($c.ClassName)|$($c.Name)|offscreen=$($c.IsOffscreen)"
      $cands = @()
      if ($c.ClassName -match 'Candidate' -or $c.Name -match 'Candidate') { $cands += $t }
      try { foreach ($e in $t.FindAll([System.Windows.Automation.TreeScope]::Descendants, $listCond)) { $cands += $e } } catch { }
      foreach ($e in $cands) {
        $ec = $null; try { $ec = $e.Current } catch { continue }
        $r = $ec.BoundingRectangle
        if ($ec.IsOffscreen -or $r.IsEmpty -or $r.Width -lt 4 -or $r.Height -lt 4 -or [double]::IsInfinity($r.Left)) { continue }
        $res += [pscustomobject]@{ Hwnd = 0; Pid = $ec.ProcessId; Proc = $pn; Cls = "uia:$($ec.ClassName)"; Title = $ec.Name; L = [int]$r.Left; T = [int]$r.Top; R = [int]$r.Right; B = [int]$r.Bottom; Visible = $true; Ex = 0; Why = 'uia-list' }
      }
    }
  } catch { $diag += "uia_exception=$($_.Exception.Message)" }
  return [pscustomobject]@{ Hits = $res; Diag = $diag }
}

# Live hit test at the moment the exe logs IMN_OPENCANDIDATE: the Microsoft IME candidate/prediction list is drawn directly below
# the caret (and is not found by EnumWindows class/process filters or UIA List search). Probe 30 px below the caret bottom and
# 30 px above the caret top (x = caret.left + 20); the root window (GA_ROOT) under each point that is not our probe window and is
# visible is the candidate window. Titles of non-ours windows are never logged.
function Cand-Hit-Probe([int]$seq) {
  try {
    # The newest open event with a caret (the list was opened by the Space that triggered this probe).
    $car = Open-Caret-Latest 0
    if ($null -eq $car) { Log "candidate_hit skipped=no_open_event_with_caret"; return }
    foreach ($h in @(Cand-Hits-Near $car 'candidate_hit')) { $script:CandHits += [pscustomobject]@{ At = $h.At; Caret = $car; W = $h.W; Seq = $seq } }
  } catch { Log "candidate_hit exception=$($_.Exception.Message)" }
}
# Hit test around one caret rect (screen px): below and above it, as described above. Returns @{At; W} per visible non-probe hit.
function Cand-Hits-Near([int[]]$car, [string]$tag) {
  $out = @()
  try {
    $pts = @(
      [pscustomobject]@{ At = 'below'; X = [int]($car[0] + 20); Y = [int]($car[1] + $car[3] + 30) },
      [pscustomobject]@{ At = 'above'; X = [int]($car[0] + 20); Y = [int]($car[1] - 30) })
    foreach ($p in $pts) {
      $root = [SRN.N]::RootAt($p.X, $p.Y)
      if ($root -eq 0) { Log "$tag at=$($p.At) result=none"; continue }
      if ($root -eq $script:Hwnd.ToInt64()) { Log "$tag at=$($p.At) result=probe_window"; continue }
      $wi = [SRN.N]::InfoOf([IntPtr]$root)
      $pn = Proc-Name ([uint32]$wi.Pid)
      if (-not $wi.Visible) { Log "$tag at=$($p.At) result=hidden class=$($wi.Cls) process=$pn"; continue }
      # Title deliberately not copied into the logged object (redaction): only class / process / rect are logged.
      # L..B = visible (DWM) rect, the one the anchoring rule uses; RawL..RawB = GetWindowRect with the invisible border.
      $w = [pscustomobject]@{ Hwnd = $wi.Hwnd; Pid = $wi.Pid; Proc = $pn; Cls = $wi.Cls; Title = ''; L = $wi.VL; T = $wi.VT; R = $wi.VR; B = $wi.VB; RawL = $wi.L; RawT = $wi.T; RawR = $wi.R; RawB = $wi.B; VisFallback = $wi.VisFallback; Visible = $true; Ex = $wi.ExStyle; Why = "$tag at=$($p.At)" }
      Log "$tag at=$($p.At) class=$($wi.Cls) process=$pn visible_rect=$($w.L),$($w.T),$($w.R),$($w.B) raw_rect=$($wi.L),$($wi.T),$($wi.R),$($wi.B) dwm=$(if ($wi.VisFallback) { 'fallback' } else { 'ok' }) caret=$($car -join ',')"
      $out += [pscustomobject]@{ At = $p.At; W = $w }
    }
  } catch { Log "$tag exception=$($_.Exception.Message)" }
  return ,$out
}
# R9 layout move: the renderer re-places the IME windows when layout moves the composing field (`ime_replace reason=layout
# old=l,t,w,h new=l,t,w,h`, CLIENT px of the caret). For each new line: convert both rects to screen (same origin logic as
# Eval-PositionSet: ClientOrigin + client px), wait 400 ms for the IME to follow, then hit-test below/above the NEW caret.
function Layout-Trigger {
  $all = @(Exe-ErrLines)
  for ($i = 0; $i -lt $all.Count; $i++) {
    if ($script:LayoutDone.ContainsKey($i)) { continue }
    $l = [string]$all[$i]
    if ($l -notmatch 'ime_replace reason=layout') { continue }
    $script:LayoutDone[$i] = $true
    if ($l -notmatch 'old=(-?\d+),(-?\d+),(-?\d+),(-?\d+) new=(-?\d+),(-?\d+),(-?\d+),(-?\d+)') { Log "candidate_after_layout line=$i skipped=unparsed"; continue }
    $oc = @([int]$Matches[1], [int]$Matches[2], [int]$Matches[3], [int]$Matches[4])
    $nc = @([int]$Matches[5], [int]$Matches[6], [int]$Matches[7], [int]$Matches[8])
    $o = [SRN.N]::ClientOrigin($script:Hwnd)
    $oldS = [int[]]@(($o[0] + $oc[0]), ($o[1] + $oc[1]), $oc[2], $oc[3])
    $newS = [int[]]@(($o[0] + $nc[0]), ($o[1] + $nc[1]), $nc[2], $nc[3])
    $scale = [SRN.N]::GetDpiForWindow($script:Hwnd) / 96.0
    Log "candidate_after_layout line=$i caret_old_screen=$($oldS -join ',') caret_new_screen=$($newS -join ',') scale=$scale wait_ms=400"
    Start-Sleep -Milliseconds 400
    $hits = @(Cand-Hits-Near $newS 'candidate_after_layout')
    Log "candidate_after_layout line=$i hits=$($hits.Count)"
    $script:LayoutRes += [pscustomobject]@{ Idx = $i; Old = $oldS; New = $newS; Scale = $scale; Hits = $hits }
  }
}

# Evidence capture (R9 candidate diagnosis): screenshot of OUR probe window + 300 px margin only (CopyFromScreen of that rect), and a full
# EnumWindows dump (visible AND invisible) of every IME-related window (class / process / title match) plus every window overlapping the
# probe region. Called right after Space press 1, and again ~1.2 s later in case the list is delayed.
function Capture-Evidence([string]$tag) {
  try {
    $all = Snap-Windows
    $me = $all | Where-Object { $_.Hwnd -eq $script:Hwnd.ToInt64() } | Select-Object -First 1
    if ($me -ne $null) {
      $mg = 300
      $x = [math]::Max(0, $me.L - $mg); $y = [math]::Max(0, $me.T - $mg)
      $w = ($me.R - $me.L) + 2 * $mg; $h = ($me.B - $me.T) + 2 * $mg
      $bmp = New-Object System.Drawing.Bitmap($w, $h)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.CopyFromScreen($x, $y, 0, 0, (New-Object System.Drawing.Size($w, $h)))
      $png = "$Out.cand-$tag.png"
      $bmp.Save($png, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()
      Log "candidate_evidence tag=$tag screenshot=$png region=$x,$y,$w,$h probe_rect=$($me.L),$($me.T),$($me.R),$($me.B)"
    } else { Log "candidate_evidence tag=$tag screenshot=none (probe window not in EnumWindows)" }
    $n = 0
    foreach ($w in $all) {
      $ov = $false
      if ($me -ne $null) { $ov = ($w.R -gt $me.L - 300 -and $w.L -lt $me.R + 300 -and $w.B -gt $me.T - 300 -and $w.T -lt $me.B + 300 -and $w.Visible) }
      if ((Is-ImeWin $w) -or $ov) { $n++; Log ("candidate_evidence tag=$tag win ime=$(Is-ImeWin $w) overlap=$ov " + (Fmt-Win $w)) }
    }
    Log "candidate_evidence tag=$tag total_top_windows=$($all.Count) listed=$n"
    $u = Candidate-Uia
    Log ("candidate_evidence tag=$tag uia_roots=[" + ($u.Diag -join '; ') + "] uia_hits=" + @($u.Hits).Count)
  } catch { Log "candidate_evidence tag=$tag exception=$($_.Exception.Message)" }
}
$script:CandSeen = $null   # last EnumWindows hit seen right after any Space press (the list can vanish before the final measurement)
function Measure-Candidate([string]$row, [string]$v0, $before) {
  Start-Sleep -Milliseconds 500
  Layout-Trigger
  $el = Edit $row
  $caret = Caret-Info $el
  $startRect = Char-Rect $el (Cp-Count $v0)
  $cw = Candidate-Windows $before
  $scale = [SRN.N]::GetDpiForWindow($script:Hwnd) / 96.0
  $via = 'enumwindows'
  $cand = $cw.Hit | Sort-Object @{ Expression = { if ($_.Cls -match 'Candidate' -or $_.Title -match 'Candidate') { 0 } else { 1 } } }, @{ Expression = { ($_.R - $_.L) * ($_.B - $_.T) } } | Select-Object -First 1
  $uiaDiag = ''
  if ($cand -eq $null) {
    $u = Candidate-Uia; $uiaDiag = ($u.Diag -join '; ')
    $cand = $u.Hits | Sort-Object @{ Expression = { ($_.R - $_.L) * ($_.B - $_.T) } } | Select-Object -First 1
    if ($cand -ne $null) { $via = 'uia' }
  }
  if ($cand -eq $null -and $script:CandSeen -ne $null) { $cand = $script:CandSeen; $via = 'enumwindows-seen-during-space-presses' }
  # exe-side evidence (ime_cand lines since this composition began): any visible IME/Candidate window anchored to the logged caret wins.
  $exeEv = Parse-ImeCand $script:CompStartIdx
  $exeBest = $null; $exeCaret = $null
  foreach ($e in $exeEv) {
    # open-time pairs only: the candidate list and the caret of the same IMN_OPENCANDIDATE (change lines move the caret later)
    if ($e.Caret -eq $null -or $e.Event -ne 'open') { continue }
    foreach ($w in (Cand-UiWins $e)) {
      $a = Anchored-To $e.Caret $w $scale
      if ($exeBest -eq $null -or ($a.Ok -and -not $exeBest.A.Ok)) { $exeBest = [pscustomobject]@{ W = $w; A = $a; E = $e } }
    }
  }
  if ($exeBest -ne $null) {
    $w = $exeBest.W; $cand = [pscustomobject]@{ Hwnd = 0; Pid = 0; Proc = 'exe-log'; Cls = $w.Cls; Title = ''; L = $w.L; T = $w.T; R = $w.R; B = $w.B; Visible = $true; Ex = 0; Why = "exe ime_cand event=$($exeBest.E.Event)" }
    $exeCaret = $exeBest.E.Caret; $via = 'exe-ime_cand'
  }
  # live hit-test candidates taken at ime_cand open events of this composition (see Cand-Hit-Probe); anchored hits override the
  # EnumWindows / UIA / exe-log choice, and an unanchored hit is used only when nothing else was found.
  $openBefore = @(@(Exe-ErrLines | Select-Object -First $script:CompStartIdx) | Where-Object { $_ -match 'ime_cand event=open' }).Count
  $hitBest = $null
  foreach ($h in @($script:CandHits | Where-Object { $_.Seq -gt $openBefore })) {
    $a = Anchored-To $h.Caret $h.W $scale
    if ($hitBest -eq $null -or ($a.Ok -and -not $hitBest.A.Ok)) { $hitBest = [pscustomobject]@{ H = $h; A = $a } }
  }
  Log ("candidate_probe hit_candidates=$(@($script:CandHits | Where-Object { $_.Seq -gt $openBefore }).Count) best=$(if ($hitBest) { "$($hitBest.H.At) anchored=$($hitBest.A.Ok)" } else { 'none' })")
  if ($hitBest -ne $null -and ($hitBest.A.Ok -or $exeBest -eq $null)) {
    $cand = $hitBest.H.W; $exeCaret = $hitBest.H.Caret; $via = 'candidate-hit-' + $hitBest.H.At
  }
  if ($cand -eq $null) { $via = 'none' }
  Log ("candidate_probe exe_ime_cand_lines=$(@($exeEv).Count) opens=$(@($exeEv | Where-Object { $_.Event -eq 'open' }).Count) with_visible_ui_window=$(@($exeEv | Where-Object { @(Cand-UiWins $_).Count -gt 0 }).Count) best=$(if ($exeBest) { "$($exeBest.W.Cls)@$($exeBest.W.L),$($exeBest.W.T),$($exeBest.W.R),$($exeBest.W.B) anchored=$($exeBest.A.Ok)" } else { 'none' })")
  Log ("candidate_probe caret_rect=$(Fmt-Rect $caret.CaretRect) comp_start_rect=$(Fmt-Rect $startRect) scale=$scale via=$via")
  Log ("candidate_probe changed_windows=[" + (($cw.New | ForEach-Object { (Fmt-Win $_) + "|why=$($_.Why)" }) -join '; ') + "]")
  Log ("candidate_probe ime_related_windows=[" + (($cw.Ime | ForEach-Object { (Fmt-Win $_) + "|why=$($_.Why)" }) -join '; ') + "]")
  if ($uiaDiag) { Log "candidate_probe uia_ime_roots=[$uiaDiag]" }
  if ($cand -ne $null) { Log "candidate_probe chosen=$(Fmt-Win $cand) why=$($cand.Why)" }
  # CompCaret = the exe-logged caret rect of THIS composition (last ime_cand line since it began, open or change). It is the
  # reference for the follow-after-commit check; the UIA rectangle is not used for it.
  $compWithCaret = @($exeEv | Where-Object { $null -ne $_.Caret })
  $compCaret = if ($compWithCaret.Count -gt 0) { [int[]]$compWithCaret[$compWithCaret.Count - 1].Caret } else { $null }
  # anchored check reference = OPEN-time caret (the one the candidate was measured with), never the post-move caret
  $openCaret = Open-Caret-Latest $script:CompStartIdx
  $bounds = if ($exeCaret -ne $null) { $exeCaret } elseif ($openCaret -ne $null) { $openCaret } elseif ($compCaret -ne $null) { $compCaret } else { Last-CaretBounds }
  Log "candidate_probe exe_caret_bounds_screen=$(Fmt-Rect $bounds) comp_exe_caret=$(Fmt-Rect $compCaret)"
  return [pscustomobject]@{ ExeEv = $exeEv; Candidate = $cand; Caret = $caret; Start = $startRect; Bounds = $bounds; CompCaret = $compCaret; Scale = $scale; New = $cw.New; Via = $via }
}
# Anchoring: the candidate must sit just below the caret (top within caret.bottom +/- 40 px) or just above it (bottom within caret.top +/- 40 px),
# and horizontally near it (left within 60 px of caret.x, or the caret x inside the candidate's span +/- 60 px); all px scaled by DPI.
function Eval-Anchor($m) {
  if ($m.Candidate -eq $null) { return $null }
  # reference = what the exe returned to the IME as the caret rectangle (storeCaretBounds, EVT ime/caret-bounds); the UIA
  # rectangle of the first composed character is the fallback for an exe that does not log bounds.
  $ref = if ($m.Bounds -ne $null) { $m.Bounds } else { $m.Start }
  if ($ref -eq $null) { return $null }
  $c = $m.Candidate; $s = $m.Scale
  $caretX = $ref[0]; $caretTop = $ref[1]; $caretBottom = $ref[1] + $ref[3]
  $dx = $c.L - $caretX; $dyBelow = $c.T - $caretBottom; $dyAbove = $c.B - $caretTop
  $below = [math]::Abs($dyBelow) -le 40 * $s
  $above = [math]::Abs($dyAbove) -le 40 * $s
  $xOk = ([math]::Abs($dx) -le 60 * $s) -or (($caretX -ge $c.L - 60 * $s) -and ($caretX -le $c.R + 60 * $s))
  return [pscustomobject]@{ Ok = (($below -or $above) -and $xOk); Dx = $dx; Dy = $dyBelow; DyAbove = $dyAbove; Placement = $(if ($below) { 'below' } elseif ($above) { 'above' } else { 'neither' }); XOk = $xOk }
}

# Position-set evidence (separate from visibility): did an IMN_OPENCANDIDATE fire whose candidate form (client px -> screen) sits at the logged caret?
function Eval-PositionSet($m) {
  $o = [SRN.N]::ClientOrigin($script:Hwnd); $s = $m.Scale
  $opens = @($m.ExeEv | Where-Object { $_.Event -eq 'open' })
  if ($opens.Count -eq 0) { return [pscustomobject]@{ Fired = $false; Match = $false; Note = 'no IMN_OPENCANDIDATE logged'; Vis = 0 } }
  $match = $false; $note = @(); $vis = 0
  foreach ($e in $opens) {
    $vis += @(Cand-UiWins $e).Count
    if ($e.Caret -eq $null) { $note += 'caret=none'; continue }
    $px = $o[0] + $e.Px; $py = $o[1] + $e.Py
    $dx = $px - $e.Caret[0]; $dyB = $py - ($e.Caret[1] + $e.Caret[3]); $dyT = $py - $e.Caret[1]
    $ok = ($e.Got -ne 0) -and ([math]::Abs($dx) -le 60 * $s) -and (([math]::Abs($dyB) -le 40 * $s) -or ([math]::Abs($dyT) -le 40 * $s))
    if ($ok) { $match = $true }
    $note += "got=$($e.Got) style=0x$('{0:X}' -f $e.Style) form_screen=$px,$py caret=$($e.Caret -join ',') dx=$dx dy_bottom=$dyB ok=$ok"
  }
  return [pscustomobject]@{ Fired = $true; Match = $match; Note = ($note | Select-Object -First 3) -join ' ; '; Vis = $vis }
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
  $idxBefore = [array]::IndexOf((Edit-Names), $row)
  $obs1 = Type-And-Observe $row $v0 'nihonn'
  $lay1Start = $script:CompStartIdx
  $expect1 =@('n', $NI, ($NI + 'h'), ($NI + $HO), ($NI + $HO + 'n'), ($NI + $HO + $NN))
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
  $winBefore = Snap-Windows   # snapshot immediately before the first Space
  $sp = Space-Until $row $v0 $NIPPON 4 $winBefore
  Add-Check 'conversion-to-nihon' $(if ($sp.Reached) { 'PASS' } else { 'FAIL' }) "Space presses=$($sp.Presses) marked after each press=[$($sp.Seen -join ' | ')] (target = the two ideographs for Japan; candidate order depends on the user's IME history, up to 4 presses allowed)"
  $m1 = Measure-Candidate $row $v0 $winBefore
  $a1 = Eval-Anchor $m1

  # ------------------------------------------------------------ candidate follows a layout move (F8: row above removed mid-composition)
  $lay = @($script:LayoutRes | Where-Object { $_.Idx -ge $lay1Start })
  if ($lay.Count -eq 0) {
    Add-Check 'candidate-window-follows-layout-move' 'NOT-RUN' 'no ime_replace reason=layout during composition 1 (the composing field did not move)'
  } else {
    $r = $lay[0]; $s = $r.Scale
    $bh = $null
    foreach ($h in @($script:CandHits | Where-Object { [math]::Abs($_.Caret[0] - $r.Old[0]) -le 2 -and [math]::Abs($_.Caret[1] - $r.Old[1]) -le 2 })) {
      if ($bh -eq $null -or ((Anchored-To $r.Old $h.W $s).Ok -and -not (Anchored-To $r.Old $bh.W $s).Ok)) { $bh = $h }
    }
    $ah = $null
    foreach ($h in @($r.Hits)) {
      if ($ah -eq $null -or ((Anchored-To $r.New $h.W $s).Ok -and -not (Anchored-To $r.New $ah.W $s).Ok)) { $ah = $h }
    }
    $bW = if ($bh) { $bh.W } else { $null }; $aW = if ($ah) { $ah.W } else { $null }
    if ($bW -eq $null -or $aW -eq $null) {
      Add-Check 'candidate-window-follows-layout-move' 'FAIL' "candidate not located: open-time candidate at the pre-move caret=$(if ($bW) { Fmt-Win $bW } else { 'none' }) ; candidate 400 ms after the move=$(if ($aW) { Fmt-Win $aW } else { 'none' }) ; caret old=$($r.Old -join ',') new=$($r.New -join ',') (screen px)"
    } else {
      $kdx = $r.New[0] - $r.Old[0]; $kdy = $r.New[1] - $r.Old[1]; $kLen = [math]::Sqrt($kdx * $kdx + $kdy * $kdy)
      $cdx = $aW.L - $bW.L; $cdy = $aW.T - $bW.T; $tol = 12 * $s
      $anch = Anchored-To $r.New $aW $s
      $moved = $kLen -gt 10 * $s
      $okL = $moved -and ([math]::Abs($cdx - $kdx) -le $tol) -and ([math]::Abs($cdy - $kdy) -le $tol) -and $anch.Ok
      Add-Check 'candidate-window-follows-layout-move' $(if ($okL) { 'PASS' } else { 'FAIL' }) ("caret old=$($r.Old -join ',') new=$($r.New -join ',') move=($kdx,$kdy) len=$([math]::Round($kLen)) (must exceed $([math]::Round(10 * $s))); candidate visible rect before=$($bW.L),$($bW.T),$($bW.R),$($bW.B) after=$($aW.L),$($aW.T),$($aW.R),$($aW.B) move=($cdx,$cdy) (per-axis tolerance $([math]::Round($tol))); anchored to NEW caret=$($anch.Ok) placement=$($anch.Placement) dx=$([math]::Round($anch.Dx)) top-caret.bottom=$([math]::Round($anch.Dy)) bottom-caret.top=$([math]::Round($anch.DyAbove)) (scale=$s)")
    }
  }

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
    [void](Type-And-Observe $row $v1 'nihonn')
    $winBefore2 = Snap-Windows
    $sp2 = Space-Until $row $v1 $NIPPON 1 $winBefore2
    $m2 = Measure-Candidate $row $v1 $winBefore2
    $a2 = Eval-Anchor $m2
    foreach ($pair in @(@('comp1', $m1), @('comp2', $m2))) {
      $ps = Eval-PositionSet $pair[1]
      $visTxt = if ($ps.Vis -gt 0) { "candidate list VISIBLE (IME window(s) seen at open: $($ps.Vis))" } else { 'candidate list NOT visible to EnumWindows at open (visibility unproven; see screenshots)' }
      Add-Check "candidate-position-set-at-caret-$($pair[0])" $(if ($ps.Fired -and $ps.Match) { 'PASS' } elseif ($ps.Fired) { 'FAIL' } else { 'NOT-RUN' }) "$($ps.Note); $visTxt"
    }
    if ($m1.Candidate -eq $null -or $m2.Candidate -eq $null) {
      $newDesc = ((@($m1.New) + @($m2.New)) | ForEach-Object { Fmt-Win $_ }) -join '; '
      Add-Check 'candidate-window-anchored-to-caret' 'FAIL' "no IME candidate window was found after Space by EnumWindows (new / became-visible / moved, IME-related class or process) nor by UIA List search (comp1 found=$($m1.Candidate -ne $null) comp2 found=$($m2.Candidate -ne $null)); exe-logged caret bounds comp1=$(Fmt-Rect $m1.Bounds) comp2=$(Fmt-Rect $m2.Bounds) (screen px) so the expected anchor is known but the IME's window was not located; windows changed after Space: [$newDesc] (see candidate_probe ime_related_windows / uia_ime_roots log lines)"
    } elseif ($a1 -eq $null -or $a2 -eq $null) {
      Add-Check 'candidate-window-anchored-to-caret' 'FAIL' "candidate window found (comp1 $($m1.Candidate.L),$($m1.Candidate.T); comp2 $($m2.Candidate.L),$($m2.Candidate.T)) but neither the exe-logged caret bounds (comp1=$(Fmt-Rect $m1.Bounds) comp2=$(Fmt-Rect $m2.Bounds)) nor the UIA rectangle (comp1=$(Fmt-Rect $m1.Start) comp2=$(Fmt-Rect $m2.Start)) was available, so anchoring cannot be judged"
    } else {
      # Follow check: movement of the candidate window's visible rect between the two compositions vs movement of the exe-logged
      # caret rect of each composition (CompCaret). Both are compared as 2-D vectors; the UIA rectangle is not used here.
      $kc1 = $m1.CompCaret; $kc2 = $m2.CompCaret
      if ($kc1 -eq $null -or $kc2 -eq $null) { $shiftOk = $false }
      $cdx = $m2.Candidate.L - $m1.Candidate.L; $cdy = $m2.Candidate.T - $m1.Candidate.T
      $shiftCand = [math]::Sqrt($cdx * $cdx + $cdy * $cdy)
      if ($kc1 -ne $null -and $kc2 -ne $null) {
        $kdx = $kc2[0] - $kc1[0]; $kdy = $kc2[1] - $kc1[1]
        $shiftComp = [math]::Sqrt($kdx * $kdx + $kdy * $kdy)
        $shiftOk = ([math]::Abs($shiftCand - $shiftComp) -le 12 * $m1.Scale) -and ($shiftComp -gt 10 * $m1.Scale)
      } else { $shiftComp = 0 }
      Add-Check 'candidate-window-anchored-to-caret' $(if ($a1.Ok -and $a2.Ok) { 'PASS' } else { 'FAIL' }) ("candidate vs exe-logged caret rect (screen px, scale=$($m1.Scale)): comp1 caret=$(Fmt-Rect $(if ($m1.Bounds -ne $null) { $m1.Bounds } else { $m1.Start })) cand=[$(Fmt-Win $m1.Candidate)] via=$($m1.Via) placement=$($a1.Placement) dx=$([math]::Round($a1.Dx)) top-caret.bottom=$([math]::Round($a1.Dy)) bottom-caret.top=$([math]::Round($a1.DyAbove)) xOk=$($a1.XOk); comp2 caret=$(Fmt-Rect $(if ($m2.Bounds -ne $null) { $m2.Bounds } else { $m2.Start })) cand=[$(Fmt-Win $m2.Candidate)] via=$($m2.Via) placement=$($a2.Placement) dx=$([math]::Round($a2.Dx)) top-caret.bottom=$([math]::Round($a2.Dy)) bottom-caret.top=$([math]::Round($a2.DyAbove)) xOk=$($a2.XOk); rule: candidate top within caret.bottom +/-40*scale (below) or bottom within caret.top +/-40*scale (above), and left within 60*scale of caret.x or caret.x inside the candidate span +/-60*scale")
      Add-Check 'candidate-window-follows-caret-after-commit' $(if ($shiftOk) { 'PASS' } else { 'FAIL' }) "exe-logged caret per composition: comp1=$(Fmt-Rect $m1.CompCaret) comp2=$(Fmt-Rect $m2.CompCaret) caret moved $([math]::Round($shiftComp)) px; candidate visible rect comp1=$($m1.Candidate.L),$($m1.Candidate.T) comp2=$($m2.Candidate.L),$($m2.Candidate.T) moved $([math]::Round($shiftCand)) px (tolerance 12*scale; caret must move > 10*scale; no exe caret for a composition = FAIL)"
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
