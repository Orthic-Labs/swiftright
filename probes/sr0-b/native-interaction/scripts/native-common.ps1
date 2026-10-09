# SR0 lane R9: shared helpers for the native-interaction drivers (dot-sourced by drive-ime.ps1 / drive-narrator.ps1).
# Runs INSIDE an interactive desktop session (one-shot scheduled task, see schedule-native.ps1). ASCII only: Windows
# PowerShell 5.1 reads a BOM-less file as ANSI, so every non-ASCII character below is built from a code point.
#
# Input policy (same contract as probes/sr0-s/fresh-on-bridge/scripts/drive-fixture.ps1, global path):
#  * keys are virtual keys through SendInput (wVk + scan code). KEYEVENTF_UNICODE / VK_PACKET is never used: it bypasses the IME.
#  * every event is gated: the probe window is brought to the foreground, LockSetForegroundWindow(1) is held, and the
#    foreground window is re-checked before each key-down and after it. Any mismatch ABORTS the run: no further key is sent.
#    (A key already pressed is released, because a stuck key is worse than one stray key-up.)
#  * there are no global hotkeys: the IME is switched with window-targeted messages to the probe's own thread.
$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
if (-not ('SRN.N' -as [type])) {
  $refs = @([System.Windows.Automation.AutomationElement].Assembly.Location, [System.Windows.Automation.ControlType].Assembly.Location)
  Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'NativeHelpers.cs'))) -ReferencedAssemblies $refs
}
if (-not [SRN.N]::SetProcessDpiAwarenessContext([IntPtr]-4)) { [void][SRN.N]::SetProcessDPIAware() }

$script:Lines = New-Object System.Collections.Generic.List[string]
$script:Checks = New-Object System.Collections.Generic.List[object]
$script:Hwnd = [IntPtr]::Zero
$script:Proc = $null
$script:StdTap = $null
$script:ErrTap = $null
$script:AbortReason = $null
$script:InputLocked = $false
$script:KeysSent = 0
$script:T0 = [Diagnostics.Stopwatch]::StartNew()

function Log([string]$s) { $script:Lines.Add(('{0,7:N1}s {1}' -f ($script:T0.ElapsedMilliseconds / 1000.0), $s)) }

# Status vocabulary: PASS, FAIL, FAIL-not-automatable (cannot be verified honestly without a person), NOT-RUN (a
# precondition failed or the budget ran out), INFO (recorded, not a verdict).
function Add-Check([string]$id, [string]$status, [string]$detail) {
  $script:Checks.Add([pscustomobject]@{ Id = $id; Status = $status; Detail = $detail })
  Log "CHECK $id $status :: $detail"
}

function U([int]$cp) { return [string][char]$cp }
# Fullwidth Latin (pending romaji in a hiragana composition) to ASCII, for tolerant comparison.
function Norm-Width([string]$s) {
  $sb = New-Object System.Text.StringBuilder
  foreach ($c in $s.ToCharArray()) {
    $v = [int]$c
    if ($v -ge 0xFF21 -and $v -le 0xFF5A) { [void]$sb.Append([char]($v - 0xFEE0)) } else { [void]$sb.Append($c) }
  }
  return $sb.ToString()
}

# ---------------------------------------------------------------- artifact identity and launch
function Verify-Tree([string]$Base, [string]$ExpectExe, [string]$ExpectDll) {
  $bin = "$Base\scratch\out\Products\Release-windows-x86_64"
  $exe = (Get-FileHash -Algorithm SHA256 -LiteralPath "$bin\FreshOnBridge.exe").Hash
  $dll = (Get-FileHash -Algorithm SHA256 -LiteralPath "$bin\swiftright_render.dll").Hash
  $ok = ($exe -eq $ExpectExe.ToUpper()) -and ($dll -eq $ExpectDll.ToUpper())
  Log "ARTIFACTS exe=$exe renderer=$dll expect_exe=$ExpectExe expect_dll=$ExpectDll match=$ok"
  return $ok
}

function Start-Fixture([string]$Base, [string]$Fixture, [string]$ReadyFile, [string]$ExtraArgs = '') {
  $bin = "$Base\scratch\out\Products\Release-windows-x86_64"
  if (Test-Path $ReadyFile) { Remove-Item -LiteralPath $ReadyFile -Force }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = Join-Path $bin 'FreshOnBridge.exe'
  $psi.Arguments = "--fixture $Fixture --ready-file `"$ReadyFile`"$(if ($ExtraArgs) { ' ' + $ExtraArgs })"
  $psi.WorkingDirectory = $bin
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
  $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
  $psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  $script:StdTap = New-Object SRN.LineTap($p, $false)
  $script:ErrTap = New-Object SRN.LineTap($p, $true)
  [void]$p.Start()
  $p.BeginOutputReadLine()
  $p.BeginErrorReadLine()
  $script:Proc = $p
  $h = [IntPtr]::Zero
  for ($i = 0; $i -lt 160 -and $h -eq [IntPtr]::Zero -and -not $p.HasExited; $i++) { Start-Sleep -Milliseconds 250; $p.Refresh(); $h = $p.MainWindowHandle }
  $script:Hwnd = $h
  Log "fixture=$Fixture pid=$($p.Id) window_hwnd=$($h.ToInt64()) polls=$i exited_early=$($p.HasExited) dpi=$(if ($h -ne [IntPtr]::Zero) { [SRN.N]::GetDpiForWindow($h) } else { 0 })"
  Start-Sleep -Milliseconds 1500
  if ($h -eq [IntPtr]::Zero) { return $null }
  return [System.Windows.Automation.AutomationElement]::FromHandle($h)
}

# Fires the exe's in-process release hook (--release-event): performs the "insert row above" engine release at this
# instant. No input is injected and no window is touched, so a real IME composition stays open.
function Signal-Release([string]$Name) {
  try { $h = [System.Threading.EventWaitHandle]::OpenExisting($Name); [void]$h.Set(); $h.Dispose(); Log "release_hook_signalled name=$Name"; return $true }
  catch { Log "release_hook_signal_failed name=$Name err=$($_.Exception.Message)"; return $false }
}

# Last caret rectangle the exe returned for the IME (EVT ime/caret-bounds, window client px), as screen [L,T,W,H].
# Null when the exe has logged none. The exe flushes stdout per EVT line, so this is live evidence.
function Last-CaretBounds {
  $evs = Parse-Evt $script:StdTap.Snapshot()
  $cb = @($evs | Where-Object { $_.kind -eq 'ime' -and $_.node_id -eq 'caret-bounds' -and $_.payload.h -gt 0 })
  if ($cb.Count -eq 0) { return $null }
  $p = $cb[$cb.Count - 1].payload
  $o = [SRN.N]::ClientOrigin($script:Hwnd)
  return @(($o[0] + [int][math]::Round($p.x)), ($o[1] + [int][math]::Round($p.y)), [int][math]::Round($p.w), [int][math]::Round($p.h))
}

function Close-And-Collect([string]$ExpectedFixture) {
  if ($script:Proc -eq $null) { return }
  if ($script:Hwnd -ne [IntPtr]::Zero -and -not $script:Proc.HasExited) {
    $ok = [SRN.N]::PostMessage($script:Hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    Log "close_window=WM_CLOSE posted=$ok"
  }
  if (-not $script:Proc.WaitForExit(90000)) { $script:Proc.Kill(); Log 'TIMEOUT: killed after 90 s' }
  $script:Proc.WaitForExit()
  Start-Sleep -Milliseconds 500   # let the async readers drain
  [void][SRN.N]::LockSetForegroundWindow(2)
  $script:InputLocked = $false
  Log "exe_exit=$($script:Proc.ExitCode) keys_sent=$($script:KeysSent) driver_abort=$(if ($script:AbortReason) { $script:AbortReason } else { 'none' })"
}

# ---------------------------------------------------------------- UI Automation helpers
$script:Root = $null
function Edit-Slot($el) {
  $id = $el.Current.AutomationId
  if ($id -match '-0*(\d+)/field$') { return "Row $($Matches[1])" }
  return $null
}
function All-Edits {
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  return $script:Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
}
function Edit([string]$name, [int]$t = 0) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    foreach ($el in (All-Edits)) { if ((Edit-Slot $el) -eq $name) { return $el } }
    if ($sw.ElapsedMilliseconds -lt $t) { Start-Sleep -Milliseconds 150 }
  } while ($sw.ElapsedMilliseconds -lt $t)
  return $null
}
function Edit-Names { return @(All-Edits | ForEach-Object { $n = Edit-Slot $_; if ($n) { $n } else { $_.Current.Name } }) }
function Find-Id([string]$automationId, [int]$t = 0) {
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $automationId)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    $el = $script:Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($el -ne $null) { return $el }
    if ($sw.ElapsedMilliseconds -lt $t) { Start-Sleep -Milliseconds 150 }
  } while ($sw.ElapsedMilliseconds -lt $t)
  return $null
}
function Find-Named([string]$name, $type, [int]$t = 0) {
  $cond = New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $type)))
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    $el = $script:Root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($el -ne $null) { return $el }
    if ($sw.ElapsedMilliseconds -lt $t) { Start-Sleep -Milliseconds 150 }
  } while ($sw.ElapsedMilliseconds -lt $t)
  return $null
}
# The uuid of a row's field automation id "row/<uuid>/field" (rows are addressed by identity, not by position).
function Row-Uuid($editEl) { if ($editEl -ne $null -and $editEl.Current.AutomationId -match '^row/([0-9A-Fa-f-]+)/field$') { return $Matches[1] }; return $null }
function Value-Of($el) {
  if ($el -eq $null) { return 'NOT_FOUND' }
  try { return $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { return "ERR $($_.Exception.Message)" }
}
function Wait-Value([string]$name, [string]$expected, [int]$timeoutMs = 30000) {
  $sw = [Diagnostics.Stopwatch]::StartNew(); $last = 'NOT_FOUND'
  while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
    $last = Value-Of (Edit $name)
    if ($last -eq $expected) { Log "wait_value[$name]=$expected ok ms=$($sw.ElapsedMilliseconds)"; return $true }
    Start-Sleep -Milliseconds 150
  }
  Log "wait_value[$name] TIMEOUT expected=[$expected] last=[$last]"
  return $false
}
function Wait-Element($getter, [string]$label, [int]$timeoutMs = 30000) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
    if ((& $getter) -ne $null) { Log "wait_element[$label] ok ms=$($sw.ElapsedMilliseconds)"; return $true }
    Start-Sleep -Milliseconds 150
  }
  Log "wait_element[$label] TIMEOUT"
  return $false
}
function Focused-Info {
  try {
    $f = [System.Windows.Automation.AutomationElement]::FocusedElement
    $slot = Edit-Slot $f
    return [pscustomobject]@{ Name = $f.Current.Name; Type = $f.Current.ControlType.ProgrammaticName; Id = $f.Current.AutomationId; Slot = $slot; Pid = $f.Current.ProcessId }
  } catch { return [pscustomobject]@{ Name = 'ERR'; Type = 'ERR'; Id = 'ERR'; Slot = $null; Pid = 0 } }
}
function Focused-Name { $i = Focused-Info; if ($i.Slot) { return $i.Slot }; return $i.Name }
function Invoke-El($el, [string]$label) {
  if ($el -eq $null) { Log "invoke[$label]=NOT_FOUND"; return $false }
  try { $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Log "invoke[$label]=ok"; return $true } catch { Log "invoke[$label]=ERR $($_.Exception.Message)"; return $false }
}
function Set-Value([string]$name, [string]$value) {
  $el = Edit $name
  if ($el -eq $null) { Log "set_value[$name]=NOT_FOUND"; return }
  try { $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($value); Log "set_value[$name]=[$value] ok" } catch { Log "set_value[$name]=ERR $($_.Exception.Message)" }
}

# ---- TextPattern: caret and ranges (same raw-provider route as probes/sr0-b/text-geometry run 4)
$script:RawGet = [System.Windows.Automation.TextPattern].Assembly.GetType('MS.Internal.Automation.UiaCoreApi').GetMethod('RawTextRange_GetBoundingRectangles', [Reflection.BindingFlags]'Static,NonPublic,Public')
$script:RangeHandle = [System.Windows.Automation.Text.TextPatternRange].GetField('_hTextRange', [Reflection.BindingFlags]'Instance,NonPublic')
$EP_START = [System.Windows.Automation.Text.TextPatternRangeEndpoint]::Start
$EP_END = [System.Windows.Automation.Text.TextPatternRangeEndpoint]::End
$TU_CHAR = [System.Windows.Automation.Text.TextUnit]::Character
# Raw provider rectangles (x,y,w,h in SCREEN pixels) for a range, or $null when unavailable. Works for a degenerate caret range.
function Raw-Rects($range) {
  try {
    $a = New-Object object[] 2
    $a[0] = $script:RangeHandle.GetValue($range)
    [void]$script:RawGet.Invoke($null, $a)
    $d = $a[1]; $out = @()
    if ($d -ne $null) { for ($i = 0; $i + 3 -lt $d.Length; $i += 4) { $out += ,([double[]]@($d[$i], $d[$i + 1], $d[$i + 2], $d[$i + 3])) } }
    return ,$out
  } catch { return $null }
}
function Cp-Count([string]$t) { $n = 0; for ($i = 0; $i -lt $t.Length; $i++) { if ([char]::IsHighSurrogate($t[$i]) -and ($i + 1) -lt $t.Length) { $i++ }; $n++ }; return $n }
# Range [a,b) in code points of a document that has n code points.
function Range-At($tp, [int]$a, [int]$b, [int]$n) {
  $r = $tp.DocumentRange.Clone()
  [void]$r.MoveEndpointByUnit($script:EP_START, $script:TU_CHAR, $a)
  [void]$r.MoveEndpointByUnit($script:EP_END, $script:TU_CHAR, ($b - $n))
  return $r
}
# Caret state of an edit through TextPattern: document text, selection start/length in UTF-16 units, caret rect (screen px).
function Caret-Info($el) {
  $info = [pscustomobject]@{ Doc = $null; SelStart16 = -1; SelLen16 = -1; SelCount = 0; CaretRect = $null; Err = $null }
  try {
    $tp = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
    $info.Doc = $tp.DocumentRange.GetText(-1)
    $sels = $tp.GetSelection(); $info.SelCount = $sels.Count
    if ($sels.Count -ge 1) {
      $s = $sels[0]
      $pre = $tp.DocumentRange.Clone()
      [void]$pre.MoveEndpointByRange($script:EP_END, $s, $script:EP_START)
      $info.SelStart16 = $pre.GetText(-1).Length
      $info.SelLen16 = $s.GetText(-1).Length
      $rr = Raw-Rects $s
      if ($rr -ne $null -and $rr.Count -ge 1) { $info.CaretRect = $rr[0] }
    }
  } catch { $info.Err = $_.Exception.Message }
  return $info
}
# Screen rectangle of the single code point at index $a of an edit's document (non-degenerate, spec-defined).
function Char-Rect($el, [int]$a) {
  try {
    $tp = $el.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)
    $n = Cp-Count $tp.DocumentRange.GetText(-1)
    if ($a -ge $n) { return $null }
    $rs = (Range-At $tp $a ($a + 1) $n).GetBoundingRectangles()
    foreach ($rc in $rs) { if (-not $rc.IsEmpty) { return [double[]]@($rc.X, $rc.Y, $rc.Width, $rc.Height) } }
  } catch { }
  return $null
}
function Fmt-Rect($r) { if ($r -eq $null) { return 'none' }; return ('{0:N0},{1:N0},{2:N0}x{3:N0}' -f $r[0], $r[1], $r[2], $r[3]) }

# ---------------------------------------------------------------- gated foreground and input
function Ensure-Foreground {
  for ($k = 0; $k -lt 20; $k++) {
    if ([SRN.N]::GetForegroundWindow() -eq $script:Hwnd) { return $true }
    $fg = [SRN.N]::GetForegroundWindow(); $pidOut = [uint32]0
    $fgThread = [SRN.N]::GetWindowThreadProcessId($fg, [ref]$pidOut)
    $me = [SRN.N]::GetCurrentThreadId()
    [void][SRN.N]::AttachThreadInput($me, $fgThread, $true)
    [void][SRN.N]::SetForegroundWindow($script:Hwnd)
    [void][SRN.N]::AttachThreadInput($me, $fgThread, $false)
    Start-Sleep -Milliseconds 120
  }
  $ok = ([SRN.N]::GetForegroundWindow() -eq $script:Hwnd)
  if (-not $ok) { Log "foreground_failed fg=[$([SRN.N]::ForegroundDescription())]" }
  return $ok
}
function Abort-Input([string]$why) {
  if (-not $script:AbortReason) { $script:AbortReason = $why }
  Log "driver_abort=$why fg=[$([SRN.N]::ForegroundDescription())] probe=$($script:Hwnd.ToInt64())"
}
# One key-down/key-up pair, gated. Returns $true when the key was delivered with the probe in the foreground throughout.
function Send-GatedKey([uint16]$vk, [string]$label, [int]$afterMs = 250) {
  return (Send-GatedChord @() $vk $label $afterMs)
}
# modifiers held (in order), then vk down/up, then modifiers released in reverse. Each down is gated individually.
function Send-GatedChord([uint16[]]$mods, [uint16]$vk, [string]$label, [int]$afterMs = 250) {
  if ($script:AbortReason) { Log "key_skipped $label reason=$($script:AbortReason)"; return $false }
  if ([SRN.N]::InputSize() -ne $(if ([IntPtr]::Size -eq 8) { 40 } else { 28 })) { Abort-Input 'INPUT-struct-size-wrong'; return $false }
  if (-not (Ensure-Foreground)) { Abort-Input 'foreground-lost'; return $false }
  [void][SRN.N]::LockSetForegroundWindow(1); $script:InputLocked = $true
  $down = New-Object System.Collections.Generic.List[uint16]
  $ok = $true
  $seq = @($mods) + @($vk)
  foreach ($k in $seq) {
    if ([SRN.N]::GetForegroundWindow() -ne $script:Hwnd) { Abort-Input "foreground-lost before-down vk=$k ($label)"; $ok = $false; break }
    $sent = [SRN.N]::SendVk($k, $false); $down.Add($k); $script:KeysSent++
    if (-not $sent) { Abort-Input "sendinput-failed vk=$k ($label)"; $ok = $false; break }
    if ([SRN.N]::GetForegroundWindow() -ne $script:Hwnd) { Abort-Input "foreground-lost after-down vk=$k ($label)"; $ok = $false; break }
    Start-Sleep -Milliseconds 35
  }
  for ($i = $down.Count - 1; $i -ge 0; $i--) { [void][SRN.N]::SendVk($down[$i], $true); Start-Sleep -Milliseconds 20 }
  Start-Sleep -Milliseconds $afterMs
  if ($ok) { Log "key $label vk=0x$($vk.ToString('X2')) mods=$(($mods | ForEach-Object { '0x' + $_.ToString('X2') }) -join '+') delivered fg_ok=true" }
  return $ok
}
function Type-Romaji([string]$romaji, [scriptblock]$afterKey) {
  foreach ($c in $romaji.ToUpper().ToCharArray()) {
    if (-not (Send-GatedKey ([uint16][int]$c) "romaji-$c")) { return $false }
    if ($afterKey -ne $null) { & $afterKey $c }
  }
  return $true
}
function Focus-Edit([string]$name) {
  $el = Edit $name 15000
  if ($el -eq $null) { Log "focus[$name]=NOT_FOUND"; return $false }
  for ($k = 0; $k -lt 4; $k++) {
    if (-not (Ensure-Foreground)) { Log "focus[$name]=not_foreground"; return $false }
    try { $el.SetFocus() } catch { Log "focus[$name]=ERR $($_.Exception.Message)" }
    Start-Sleep -Milliseconds 400
    if ((Focused-Name) -eq $name) { Log "focus[$name]=ok attempt=$k"; return $true }
  }
  Log "focus[$name]=NOT_CONFIRMED focused=[$(Focused-Name)]"
  return $false
}

# ---------------------------------------------------------------- EVT parsing (the exe's stdout, read after exit)
function Parse-Evt([string[]]$stdout) {
  $evs = New-Object System.Collections.Generic.List[object]
  foreach ($l in $stdout) {
    if ($l.StartsWith('EVT ')) { try { $evs.Add((ConvertFrom-Json $l.Substring(4))) } catch { } }
  }
  return $evs
}
function Write-Result([string]$Out, [string]$Title) {
  Add-Check 'input-gate-no-foreground-abort' $(if ($script:AbortReason) { 'FAIL' } else { 'PASS' }) "gated virtual-key events sent=$($script:KeysSent) abort=$(if ($script:AbortReason) { $script:AbortReason } else { 'none' }) (any foreground change aborts the run; no keystroke may reach another application)"
  $pass = @($script:Checks | Where-Object { $_.Status -eq 'PASS' }).Count
  $fail = @($script:Checks | Where-Object { $_.Status -eq 'FAIL' }).Count
  $fna = @($script:Checks | Where-Object { $_.Status -eq 'FAIL-not-automatable' }).Count
  $nr = @($script:Checks | Where-Object { $_.Status -eq 'NOT-RUN' }).Count
  Log "NATIVE_SUMMARY $Title pass=$pass fail=$fail fail_not_automatable=$fna not_run=$nr"
  if ($script:StdTap -ne $null) { Log '--- exe stdout ---'; foreach ($l in $script:StdTap.Snapshot()) { Log $l } }
  if ($script:ErrTap -ne $null) { Log '--- exe stderr ---'; foreach ($l in $script:ErrTap.Snapshot()) { Log $l } }
  [IO.File]::WriteAllText($Out, [string]::Join("`r`n", $script:Lines), (New-Object Text.UTF8Encoding $false))
}
