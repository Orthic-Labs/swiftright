# Drives FreshOnBridge.exe for one fixture from INSIDE an interactive desktop session (one-shot task, see
# schedule-fixture.ps1). Input is UIA (SetFocus, Invoke, ValuePattern.SetValue, WindowPattern.Close) and
# virtual keys (keybd_event). No Unicode packets are sent. Engine releases and model steps are in-process
# (the exe's self-test); this script only observes the UI state it needs to sequence input, and closes the window.
#   -Fixture F1..F9     -Variant  F3: list-0s|list-1s|list-3s|vstack-1s|vstack-3s|lazy-1s|lazy-3s
#                                  F6: reduced|override-on   F9: notasks   (empty otherwise)
param(
  [string]$Base = 'D:\Claude\sr0s-bridge',
  [string]$Fixture = 'F1',
  [string]$Variant = '',
  [string]$Out = 'D:\Claude\sr0s-bridge\result-fixture.txt',
  # Targeted message set: all (WM_KEYDOWN, WM_CHAR, WM_KEYUP as a physical key), char (WM_CHAR only), keydown (no WM_CHAR)
  [string]$KeyMode = 'char',
  # Opt-in SR0 candidate startup guard. Default keeps historical driver behavior.
  [switch]$NoActivate
)
$ErrorActionPreference = 'Continue'
$Bin = "$Base\scratch\out\Products\Release-windows-x86_64"
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace SW {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static class N {
    [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr h, int cmd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hgt, bool repaint);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint map);
    [DllImport("user32.dll")] public static extern bool LockSetForegroundWindow(uint lockCode);
  }
}
'@
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $lines.Add($s) }
if (-not [SW.N]::SetProcessDpiAwarenessContext([IntPtr]-4)) { [void][SW.N]::SetProcessDPIAware() }

$exeArgs = "--fixture $Fixture"
switch ($Fixture) {
  'F3' { if ($Variant) { $exeArgs += " --f3-variant $Variant" } }
  'F6' {
    if ($Variant -eq 'reduced') { $exeArgs += ' --reduced-motion-variant' }
    elseif ($Variant -eq 'override-on') { $exeArgs += ' --reduce-motion-override on' }
  }
  'F9' { if ($Variant -eq 'notasks') { $exeArgs += ' --f9-variant notasks' } }
}
# The exe writes "$Out.ready" when its script reaches the close step (after any settle). Close only after that.
$runNamespace = [guid]::NewGuid().ToString('N')
$readyFile = "$Out.ready.$runNamespace"
$exeArgs += " --ready-file `"$readyFile`""
$rendererReadyFile = $null
if ($NoActivate) {
  $rendererReadyFile = "$Out.renderer-ready.$runNamespace"
  $exeArgs += " --sr0-noactivate --renderer-ready-file `"$rendererReadyFile`""
}
# Delivery (default targeted): WM_KEYDOWN / WM_CHAR / WM_KEYUP are POSTED to the probe window only. No keystroke can
# reach another application, whatever has focus. Global keybd_event (-Delivery global) is used by no matrix config;
# it is gated: foreground is locked and re-checked before and after each key-down, and any mismatch aborts the run.
$delivery = if ($env:SR0S_DELIVERY) { $env:SR0S_DELIVERY } else { 'targeted' }
Log "host=$env:COMPUTERNAME session=$((Get-Process -Id $PID).SessionId) fixture=$Fixture variant=$Variant args=$exeArgs started=$(Get-Date -Format o)"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $Bin 'FreshOnBridge.exe'
$psi.Arguments = $exeArgs
$psi.WorkingDirectory = $Bin
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$proc = [System.Diagnostics.Process]::Start($psi)
$originalProcessId = $proc.Id
$originalProcessHandle = $proc.Handle
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()
$rendererReadyValid = $true

$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 160 -and $hwnd -eq [IntPtr]::Zero -and -not $proc.HasExited; $i++) {
  Start-Sleep -Milliseconds 250; $proc.Refresh(); $hwnd = $proc.MainWindowHandle
}
Log "window_hwnd=$($hwnd.ToInt64()) polls=$i exited_early=$($proc.HasExited)"
if ($NoActivate) {
  $rendererReadyWait = [Diagnostics.Stopwatch]::StartNew()
  while (-not (Test-Path -LiteralPath $rendererReadyFile) -and -not $proc.HasExited -and $rendererReadyWait.ElapsedMilliseconds -lt 45000) {
    Start-Sleep -Milliseconds 100
  }
  try {
    if (-not (Test-Path -LiteralPath $rendererReadyFile)) { throw "renderer-ready file missing" }
    $readyRaw = [IO.File]::ReadAllText($rendererReadyFile)
    $readyRecord = $readyRaw | ConvertFrom-Json
    $rendererReadyValid = ($readyRecord.record -eq 'renderer-ready' -and $readyRecord.phase -eq 'first-ready' -and
      $readyRecord.source -eq 'Bridge.onReady' -and [int]$readyRecord.pid -eq $originalProcessId -and
      [uint32]$readyRecord.width_px -gt 0 -and [uint32]$readyRecord.height_px -gt 0 -and [double]$readyRecord.scale -gt 0)
    Log "renderer_ready_event=$rendererReadyValid waited_ms=$($rendererReadyWait.ElapsedMilliseconds) record=$($readyRecord.record) phase=$($readyRecord.phase) source=$($readyRecord.source) pid=$($readyRecord.pid) owner_pid=$originalProcessId bridge_window=$($readyRecord.bridge_window)"
    if (-not $rendererReadyValid) { throw 'renderer-ready record identity/phase mismatch' }
  } catch {
    $rendererReadyValid = $false
    Log "renderer_ready_event=FAIL waited_ms=$($rendererReadyWait.ElapsedMilliseconds) error=$($_.Exception.Message)"
  }
} else {
  Log 'renderer_ready_event=UNAVAILABLE source=FreshOnBridge-stdout-no-startup-marker'
}
if ($hwnd -ne [IntPtr]::Zero) {
  [void][SW.N]::ShowWindowAsync($hwnd, 4)
  [void][SW.N]::SetWindowPos($hwnd, [IntPtr]1, 0, 0, 0, 0, 0x253)
  $windowPid = [uint32]0; [void][SW.N]::GetWindowThreadProcessId($hwnd, [ref]$windowPid)
  $wr = New-Object SW.RECT; $cr = New-Object SW.RECT
  $wrOk = [SW.N]::GetWindowRect($hwnd, [ref]$wr); $crOk = [SW.N]::GetClientRect($hwnd, [ref]$cr)
  $dpi = [SW.N]::GetDpiForWindow($hwnd)
  Log "WindowMetrics phase=startup utc=$([DateTime]::UtcNow.ToString('o')) hwnd=$($hwnd.ToInt64()) pid=$windowPid owner_pid=$originalProcessId client_ok=$crOk client=$($cr.Right-$cr.Left)x$($cr.Bottom-$cr.Top) window_ok=$wrOk window=$($wr.Right-$wr.Left)x$($wr.Bottom-$wr.Top) dpi=$dpi same_process=$($windowPid -eq $originalProcessId)"
}
Start-Sleep -Milliseconds 1500
$root = if ($hwnd -ne [IntPtr]::Zero) { [System.Windows.Automation.AutomationElement]::FromHandle($hwnd) } else { $null }

$script:targetInvalid = -not $rendererReadyValid
function Assert-Target([string]$phase) {
  if ($script:targetInvalid) { return $false }
  try {
    $proc.Refresh()
    $currentHandle = $proc.Handle
    $currentHwnd = $proc.MainWindowHandle
    $windowPid = [uint32]0
    [void][SW.N]::GetWindowThreadProcessId($hwnd, [ref]$windowPid)
    $ok = (-not $proc.HasExited) -and ($currentHwnd -eq $hwnd) -and ($windowPid -eq $originalProcessId) -and ($currentHandle -eq $originalProcessHandle)
    if (-not $ok) {
      $script:targetInvalid = $true
      Log "target_guard=FAIL phase=$phase hwnd=$($hwnd.ToInt64()) current_hwnd=$($currentHwnd.ToInt64()) pid=$windowPid owner_pid=$originalProcessId same_handle=$($currentHandle -eq $originalProcessHandle) exited=$($proc.HasExited)"
      return $false
    }
    Log "target_guard=PASS phase=$phase hwnd=$($hwnd.ToInt64()) pid=$windowPid same_handle=true"
    return $true
  } catch {
    $script:targetInvalid = $true
    Log "target_guard=FAIL phase=$phase error=$($_.Exception.Message)"
    return $false
  }
}

function Find-Named([string]$name, $type, [int]$timeoutMs = 0) {
  if ($root -eq $null) { return $null }
  $cond = New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $type)))
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($el -ne $null) { return $el }
    if ($sw.ElapsedMilliseconds -lt $timeoutMs) { Start-Sleep -Milliseconds 150 }
  } while ($sw.ElapsedMilliseconds -lt $timeoutMs)
  return $null
}
# Text fields carry no AX label (Mac oracle parity); a field is addressed by its AutomationId
# "row/<uuid>/field", whose uuid ends in the row slot. "Row N" below is the slot name used by the script.
function Edit-Slot($el) {
  $id = $el.Current.AutomationId
  if ($id -match '-0*(\d+)/field$') { return "Row $($Matches[1])" }
  return $null
}
function Edit([string]$name, [int]$t = 0) {
  if ($root -eq $null) { return $null }
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    foreach ($el in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
      if ((Edit-Slot $el) -eq $name) { return $el }
    }
    if ($sw.ElapsedMilliseconds -lt $t) { Start-Sleep -Milliseconds 150 }
  } while ($sw.ElapsedMilliseconds -lt $t)
  return $null
}
function Button([string]$name, [int]$t = 0) { Find-Named $name ([System.Windows.Automation.ControlType]::Button) $t }
function Text-Elem([string]$name, [int]$t = 0) { Find-Named $name ([System.Windows.Automation.ControlType]::Text) $t }
function Value-Of($el) {
  if ($el -eq $null) { return 'NOT_FOUND' }
  try { return $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { return "ERR $($_.Exception.Message)" }
}
function Wait-Value([string]$name, [string]$expected, [int]$timeoutMs = 30000) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $last = 'NOT_FOUND'
  while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
    $last = Value-Of (Edit $name)
    if ($last -eq $expected) { Log "wait_value[$name]=$expected ok ms=$($sw.ElapsedMilliseconds)"; return $true }
    Start-Sleep -Milliseconds 150
  }
  Log "wait_value[$name] TIMEOUT expected=[$expected] last=[$last]"
  return $false
}
function Wait-Element($el_getter, [string]$label, [int]$timeoutMs = 30000) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
    if ((& $el_getter) -ne $null) { Log "wait_element[$label] ok ms=$($sw.ElapsedMilliseconds)"; return $true }
    Start-Sleep -Milliseconds 150
  }
  Log "wait_element[$label] TIMEOUT"
  Dump-Names
  return $false
}
function Dump-Names {
  # Diagnostic: element names and control types visible under the window (first 60).
  if ($root -eq $null) { return }
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $n = 0
  foreach ($el in $all) {
    if ($n -ge 60) { break }
    Log ("uia_element name=[{0}] type={1}" -f $el.Current.Name, $el.Current.ControlType.ProgrammaticName)
    $n++
  }
}
# Keys are sent only while the test window is the foreground window. A person may be using the same desktop;
# keystrokes must never reach another application, so a failed foreground acquire aborts the input.
$script:inputAborted = $false
$script:abortReason = $null
$script:lastFg = [IntPtr]::Zero
$script:fgChanges = 0
# Records a change of the foreground window between samples (recorded per run, not acted on).
function Sample-Fg([string]$where) {
  $fg = [SW.N]::GetForegroundWindow()
  if ($fg -ne $script:lastFg) {
    $script:fgChanges++
    $t = (Get-Process | Where-Object { $_.MainWindowHandle -eq $fg } | Select-Object -First 1).MainWindowTitle
    Log "fg_change at=$where from=$($script:lastFg.ToInt64()) to=$($fg.ToInt64()) title=[$t] probe=$($hwnd.ToInt64())"
    $script:lastFg = $fg
  }
  return $fg
}
function Ensure-Foreground {
  if (-not (Assert-Target 'before-foreground')) { return $false }
  for ($k = 0; $k -lt 20; $k++) {
    if ([SW.N]::GetForegroundWindow() -eq $hwnd) { return $true }
    $fg = [SW.N]::GetForegroundWindow()
    $pidOut = [uint32]0
    $fgThread = [SW.N]::GetWindowThreadProcessId($fg, [ref]$pidOut)
    $me = [SW.N]::GetCurrentThreadId()
    [void][SW.N]::AttachThreadInput($me, $fgThread, $true)
    [void][SW.N]::SetForegroundWindow($hwnd)
    [void][SW.N]::AttachThreadInput($me, $fgThread, $false)
    Start-Sleep -Milliseconds 120
  }
  $ok = ([SW.N]::GetForegroundWindow() -eq $hwnd)
  if (-not $ok) { Log "foreground_failed fg_title=[$((Get-Process | Where-Object { $_.MainWindowHandle -eq [SW.N]::GetForegroundWindow() } | Select-Object -First 1).MainWindowTitle)]" }
  return $ok
}
function Type-Key([byte]$vk, [int]$ch = 0) {
  if (-not (Assert-Target "before-key-$vk")) { return }
  if ($delivery -eq 'global') { Type-Key-Global $vk; return }
  # Targeted: the three messages a physical key produces, posted to the probe HWND. Char = lower-case letter or the
  # unshifted OEM character (the fixtures type only these). Foreground is not required for delivery.
  $scan = [SW.N]::MapVirtualKeyW($vk, 0)
  $down = [IntPtr]([int64]1 -bor ([int64]$scan -shl 16))
  $up   = [IntPtr]([int64]1 -bor ([int64]$scan -shl 16) -bor 0x40000000 -bor 0x80000000)
  $fgBefore = Sample-Fg "key-$vk"
  $ok1 = $true; $ok2 = $true; $ok3 = $true
  if ($KeyMode -ne 'char') { $ok1 = [SW.N]::PostMessage($hwnd, 0x0100, [IntPtr]$vk, $down) }
  if ($KeyMode -ne 'keydown' -and $ch -gt 0) { $ok2 = [SW.N]::PostMessage($hwnd, 0x0102, [IntPtr]$ch, $down) }
  if ($KeyMode -ne 'char') { $ok3 = [SW.N]::PostMessage($hwnd, 0x0101, [IntPtr]$vk, $up) }
  Start-Sleep -Milliseconds 220
  Log "key vk=$vk char=$ch mode=targeted-post keymode=$KeyMode posted=$($ok1 -and $ok2 -and $ok3) fg_before=$($fgBefore.ToInt64()) fg_after=$(([SW.N]::GetForegroundWindow()).ToInt64())"
}
# Global path (not used by any matrix config). Abort, with no further keys, on any foreground mismatch.
function Type-Key-Global([byte]$vk) {
  if ($script:abortReason) { Log "key_skipped vk=$vk reason=$($script:abortReason)"; return }
  if (-not (Ensure-Foreground)) { $script:abortReason = 'foreground-lost'; Log "driver_abort=foreground-lost before=vk$vk"; return }
  [void][SW.N]::LockSetForegroundWindow(1)
  if ([SW.N]::GetForegroundWindow() -ne $hwnd) { $script:abortReason = 'foreground-lost'; Log "driver_abort=foreground-lost before-down=vk$vk"; return }
  [SW.N]::keybd_event($vk, 0, 0, [UIntPtr]::Zero)
  if ([SW.N]::GetForegroundWindow() -ne $hwnd) {
    $script:abortReason = 'foreground-lost'; Log "driver_abort=foreground-lost after-down=vk$vk fg=$(([SW.N]::GetForegroundWindow()).ToInt64())"; return
  }
  [SW.N]::keybd_event($vk, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 220
  Log "key vk=$vk mode=global fg_ok=true"
}
# Provider focus reads UIA element state published by AccessKit. It does not query
# AutomationElement.FocusedElement, which is a desktop-global foreground query.
function Provider-Focus($el) {
  try {
    $v = $el.GetCurrentPropertyValue([System.Windows.Automation.AutomationElementIdentifiers]::HasKeyboardFocusProperty)
    if ($v -is [bool]) { return [bool]$v }
    return ($v -eq $true)
  } catch { return $false }
}
function Focus-Edit([string]$name) {
  if (-not (Assert-Target "before-focus-$name")) { return }
  $el = Edit $name 15000
  if ($el -eq $null) { Log "focus[$name]=NOT_FOUND"; return }
  for ($k = 0; $k -lt 4; $k++) {
    # NoActivate keeps CBT activation/focus veto active. Skipping only this
    # foreground acquisition permits UIA provider SetFocus against inactive HWND.
    if (-not $NoActivate -and -not (Ensure-Foreground)) { Log "focus[$name]=not_foreground"; return }
    try { $el.SetFocus() } catch { Log "focus[$name]=ERR $($_.Exception.Message)" }
    Start-Sleep -Milliseconds 400
    if ($NoActivate) {
      $provider = Provider-Focus $el
      Log "provider_focus[$name]=$provider attempt=$k property=HasKeyboardFocus"
      if ($provider) { Log "focus[$name]=ok provider=HasKeyboardFocus attempt=$k"; return }
    } elseif ((Focused-Name) -eq $name) {
      Log "focus[$name]=ok attempt=$k"; return
    }
  }
  if ($NoActivate) {
    Log "focus[$name]=NOT_CONFIRMED provider=HasKeyboardFocus"
  } else {
    Log "focus[$name]=NOT_CONFIRMED focused=[$(Focused-Name)]"
  }
}
function Focused-Name { try { $f = [System.Windows.Automation.AutomationElement]::FocusedElement; $n = Edit-Slot $f; if ($n) { $n } else { $f.Current.Name } } catch { "ERR" } }
function Invoke-Named($el, [string]$label) {
  if (-not (Assert-Target "before-invoke-$label")) { return }
  if ($el -eq $null) { Log "invoke[$label]=NOT_FOUND"; return }
  try { $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Log "invoke[$label]=ok" } catch { Log "invoke[$label]=ERR $($_.Exception.Message)" }
}
function Set-Value([string]$name, [string]$value) {
  if (-not (Assert-Target "before-set-$name")) { return }
  $el = Edit $name
  if ($el -eq $null) { Log "set_value[$name]=NOT_FOUND"; return }
  try { $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($value); Log "set_value[$name]=$value ok" } catch { Log "set_value[$name]=ERR $($_.Exception.Message)" }
}
function Edit-Names {
  if ($root -eq $null) { return @() }
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
  return @($all | ForEach-Object { $n = Edit-Slot $_; if ($n) { $n } else { $_.Current.Name } })
}
function Delete-Near([string]$editName) {
  if (-not (Assert-Target "before-delete-$editName")) { return $null }
  # The Delete button on the same row as the named edit: nearest by vertical centre.
  $row = Edit $editName 15000
  if ($row -eq $null) { return $null }
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  # The UIA tree can lag one step behind the previous action, so retry the whole search
  # (fresh row and Delete FindAll from the window root) for up to 2 s at 100 ms intervals.
  $best = $null; $bestDy = [double]::MaxValue; $attempts = 0
  $sw = [Diagnostics.Stopwatch]::StartNew()
  do {
    $attempts++
    $best = $null; $bestDy = [double]::MaxValue
    $row = Edit $editName 0
    if ($row -ne $null) {
      $ry = $row.Current.BoundingRectangle.Top + $row.Current.BoundingRectangle.Height / 2
      foreach ($b in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
        if ($b.Current.Name -ne 'Delete') { continue }
        $by = $b.Current.BoundingRectangle.Top + $b.Current.BoundingRectangle.Height / 2
        $dy = [math]::Abs($by - $ry)
        if ($dy -lt $bestDy) { $bestDy = $dy; $best = $b }
      }
    }
    if ($best -ne $null) { break }
    if ($sw.ElapsedMilliseconds -lt 2000) { Start-Sleep -Milliseconds 100 }
  } while ($sw.ElapsedMilliseconds -lt 2000)
  Log "delete_near[$editName] dy=$([math]::Round($bestDy,1)) delete_near_attempts=$attempts"
  if ($best -eq $null) { Log "delete_near[$editName] NO_CANDIDATE after $attempts attempts (2 s)" }
  return $best
}
function Set-ClientDip([int]$w, [int]$h) {
  if (-not (Assert-Target "before-resize-${w}x${h}")) { return }
  $dpi = [SW.N]::GetDpiForWindow($hwnd)
  $scale = $dpi / 96.0
  $wr = New-Object SW.RECT; $cr = New-Object SW.RECT
  [void][SW.N]::GetWindowRect($hwnd, [ref]$wr); [void][SW.N]::GetClientRect($hwnd, [ref]$cr)
  $frameW = ($wr.Right - $wr.Left) - ($cr.Right - $cr.Left)
  $frameH = ($wr.Bottom - $wr.Top) - ($cr.Bottom - $cr.Top)
  $cw = [int][math]::Round($w * $scale); $ch = [int][math]::Round($h * $scale)
  [void][SW.N]::MoveWindow($hwnd, $wr.Left, $wr.Top, $cw + $frameW, $ch + $frameH, $true)
  Log "resize_client_dip=${w}x${h} dpi=$dpi client_px=${cw}x${ch}"
}
function Close-Window {
  if ($hwnd -eq [IntPtr]::Zero) { return }
  if (-not (Assert-Target 'before-close')) { Log 'close_window=SKIPPED target_guard_failed'; return }
  $ok = [SW.N]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  Log "close_window=WM_CLOSE posted=$ok"
}

if ($root -ne $null) {
  switch ($Fixture) {
    'F1' {
      Focus-Edit 'Row 5'
      Log "focused_after_focus=[$(Focused-Name)]"
      Type-Key 0x41 97; Type-Key 0x42 98; Type-Key 0x43 99
      Wait-Value 'Row 5' 'Row 5abc' | Out-Null
      Wait-Element { Edit 'Row 99' } 'inserted row 99 (Engine 0)' 30000 | Out-Null
      Type-Key 0x44 100
      Wait-Value 'Row 5' 'Row 5abcd' | Out-Null
      Log "focused_final=[$(Focused-Name)]"
    }
    'F2' {
      Focus-Edit 'Row 3'
      Type-Key 0xBD 45; Type-Key 0x58 120
      Wait-Value 'Row 3' 'Row 3-x' | Out-Null
      Start-Sleep -Milliseconds 1200
      Log "uia_edit_order=[$((Edit-Names) -join ',')]"
      Log "focused_final=[$(Focused-Name)]"
    }
    'F3' {
      Focus-Edit 'Row 4'
      Type-Key 0x58 120
      Start-Sleep -Milliseconds 2500
      Log "row4_value_after_reinsert=[$(Value-Of (Edit 'Row 4'))]"
      Log "focused_final=[$(Focused-Name)]"
    }
    'F4' {
      Start-Sleep -Milliseconds 2500
      Log "uia_edit_count=$((Edit-Names).Count)"
    }
    'F5' {
      Set-ClientDip 720 560; Start-Sleep -Milliseconds 1500
      Set-ClientDip 360 560; Start-Sleep -Milliseconds 2000
      Set-ClientDip 720 560; Start-Sleep -Milliseconds 2000
      Log "row1_value=[$(Value-Of (Edit 'Row 1'))]"
    }
    'F6' {
      Start-Sleep -Milliseconds 2500
    }
    'F7' {
      # VK keys type "ka" (keystroke path). The IME composition ("n", "na", unmark) is driven by the exe
      # through the bridge text-store API; real IME input is a separate manual check.
      Focus-Edit 'Row 2'
      Type-Key 0x4B 107; Type-Key 0x41 97
      Wait-Value 'Row 2' 'Row 2ka' | Out-Null
      Wait-Element { Edit 'Row 99' } 'inserted row 99 (Engine 0)' 30000 | Out-Null
      Wait-Value 'Row 2' 'Row 2kana' | Out-Null
      Log "focused_final=[$(Focused-Name)]"
    }
    'F8' {
      Invoke-Named (Button 'Insert above' 15000) 'Insert above'
      Wait-Element { Edit 'Row 101' } 'inserted row 101 (Toolbar 0)' 30000 | Out-Null
      Set-Value 'Row 3' 'AX value'
      Wait-Value 'Row 3' 'AX value' | Out-Null
      Focus-Edit 'Row 3'
      Log "focused_after_focus=[$(Focused-Name)]"
      $del = Delete-Near 'Row 6'
      Invoke-Named $del 'Delete (row 6)'
      Wait-Element { if ((Edit 'Row 6') -eq $null) { 'gone' } else { $null } } 'Row 6 removed' 8000 | Out-Null
      Log "uia_edit_count=$((Edit-Names).Count)"
    }
    'F9' {
      Start-Sleep -Milliseconds 3000
      Log "uia_edit_count_before_close=$((Edit-Names).Count)"
    }
  }
  $waitReady = [Diagnostics.Stopwatch]::StartNew()
  while (-not (Test-Path $readyFile) -and -not $proc.HasExited -and $waitReady.ElapsedMilliseconds -lt 45000) { Start-Sleep -Milliseconds 100 }
  Log "driver_close_ready_file=$(Test-Path $readyFile) waited_ms=$($waitReady.ElapsedMilliseconds) exe_exited=$($proc.HasExited)"
  $driverCloseReadyUtc = [DateTime]::UtcNow.ToString('o')
  $proc.Refresh()
  $readyPid = [uint32]0; [void][SW.N]::GetWindowThreadProcessId($hwnd, [ref]$readyPid)
  $rwr = New-Object SW.RECT; $rcr = New-Object SW.RECT
  $rwrOk = [SW.N]::GetWindowRect($hwnd, [ref]$rwr); $rcrOk = [SW.N]::GetClientRect($hwnd, [ref]$rcr)
  $currentProcessHandle = $proc.Handle
  Log "driver_close_ready_utc=$driverCloseReadyUtc WindowMetrics phase=driver-close-ready hwnd=$($hwnd.ToInt64()) pid=$readyPid owner_pid=$originalProcessId client_ok=$rcrOk client=$($rcr.Right-$rcr.Left)x$($rcr.Bottom-$rcr.Top) window_ok=$rwrOk window=$($rwr.Right-$rwr.Left)x$($rwr.Bottom-$rwr.Top) dpi=$([SW.N]::GetDpiForWindow($hwnd)) same_hwnd=$($hwnd -eq $proc.MainWindowHandle) same_process=$($readyPid -eq $originalProcessId) retained_handle=$(-not $proc.HasExited) same_handle=$($currentProcessHandle -eq $originalProcessHandle)"
  Close-Window
} else {
  Log 'no window: UIA root unavailable'
}

if (-not $proc.WaitForExit(90000)) { $proc.Kill(); Log 'TIMEOUT: killed after 90 s' }
$proc.WaitForExit()
[void][SW.N]::LockSetForegroundWindow(2)
Log "run_summary keymode=$KeyMode delivery=$delivery fg_changes=$($script:fgChanges) driver_abort=$(if ($script:abortReason) { $script:abortReason } else { 'none' })"
Log "exit=$($proc.ExitCode) end=$(Get-Date -Format o)"
Log '--- stdout ---'
Log ([string]$stdout.Result)
Log '--- stderr ---'
Log ([string]$stderr.Result)
# Artifact identity for qualification: exe and renderer hashes plus the run trace (the exe event stdout, UTF-8).
$traceHash = ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$stdout.Result))) -replace '-','').ToLower()
$artExe = (Get-FileHash -Algorithm SHA256 -LiteralPath "$Bin\FreshOnBridge.exe").Hash.ToLower()
$artDll = (Get-FileHash -Algorithm SHA256 -LiteralPath "$Bin\swiftright_render.dll").Hash.ToLower()
Log "ARTIFACTS exe=$artExe renderer=$artDll trace=$traceHash"
[System.IO.File]::WriteAllText($Out, [string]::Join("`r`n", $lines))
