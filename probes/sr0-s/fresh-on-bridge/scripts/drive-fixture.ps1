# Drives FreshOnBridge.exe for one fixture from INSIDE an interactive desktop session (one-shot task, see
# schedule-fixture.ps1). Input is UIA (SetFocus, Invoke, ValuePattern.SetValue, WindowPattern.Close) and
# virtual keys (keybd_event). No Unicode packets are sent. Engine releases and model steps are in-process
# (the exe's self-test); this script only observes the UI state it needs to sequence input, and closes the window.
#   -Fixture F1..F9     -Variant  F3: list-0s|list-1s|list-3s|vstack-1s|vstack-3s|lazy-1s
#                                  F6: reduced|override-on   F9: notasks   (empty otherwise)
param(
  [string]$Base = 'D:\Claude\sr0s-bridge',
  [string]$Fixture = 'F1',
  [string]$Variant = '',
  [string]$Out = 'D:\Claude\sr0s-bridge\result-fixture.txt'
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
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hgt, bool repaint);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
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
Log "host=$env:COMPUTERNAME session=$((Get-Process -Id $PID).SessionId) fixture=$Fixture variant=$Variant args=$exeArgs started=$(Get-Date -Format o)"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $Bin 'FreshOnBridge.exe'
$psi.Arguments = $exeArgs
$psi.WorkingDirectory = $Bin
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()

$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 160 -and $hwnd -eq [IntPtr]::Zero -and -not $proc.HasExited; $i++) {
  Start-Sleep -Milliseconds 250; $proc.Refresh(); $hwnd = $proc.MainWindowHandle
}
Log "window_hwnd=$($hwnd.ToInt64()) polls=$i exited_early=$($proc.HasExited)"
Start-Sleep -Milliseconds 1500
$root = if ($hwnd -ne [IntPtr]::Zero) { [System.Windows.Automation.AutomationElement]::FromHandle($hwnd) } else { $null }

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
function Edit([string]$name, [int]$t = 0) { Find-Named $name ([System.Windows.Automation.ControlType]::Edit) $t }
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
function Ensure-Foreground {
  for ($k = 0; $k -lt 20; $k++) {
    if ([SW.N]::GetForegroundWindow() -eq $hwnd) { return $true }
    $fg = [SW.N]::GetForegroundWindow()
    $pidOut = [IntPtr]::Zero
    $fgThread = [SW.N]::GetWindowThreadProcessId($fg, $pidOut)
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
function Type-Key([byte]$vk) {
  if ($script:inputAborted -or -not (Ensure-Foreground)) {
    $script:inputAborted = $true
    Log "key_skipped vk=$vk reason=not_foreground"
    return
  }
  [SW.N]::keybd_event($vk, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
  [SW.N]::keybd_event($vk, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 220
}
function Focus-Edit([string]$name) {
  $el = Edit $name 15000
  if ($el -eq $null) { Log "focus[$name]=NOT_FOUND"; return }
  for ($k = 0; $k -lt 4; $k++) {
    if (-not (Ensure-Foreground)) { $script:inputAborted = $true; Log "focus[$name]=not_foreground"; return }
    try { $el.SetFocus() } catch { Log "focus[$name]=ERR $($_.Exception.Message)" }
    Start-Sleep -Milliseconds 400
    if ((Focused-Name) -eq $name) { Log "focus[$name]=ok attempt=$k"; return }
  }
  Log "focus[$name]=NOT_CONFIRMED focused=[$(Focused-Name)]"
}
function Focused-Name { try { [System.Windows.Automation.AutomationElement]::FocusedElement.Current.Name } catch { "ERR" } }
function Invoke-Named($el, [string]$label) {
  if ($el -eq $null) { Log "invoke[$label]=NOT_FOUND"; return }
  try { $el.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Log "invoke[$label]=ok" } catch { Log "invoke[$label]=ERR $($_.Exception.Message)" }
}
function Set-Value([string]$name, [string]$value) {
  $el = Edit $name
  if ($el -eq $null) { Log "set_value[$name]=NOT_FOUND"; return }
  try { $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($value); Log "set_value[$name]=$value ok" } catch { Log "set_value[$name]=ERR $($_.Exception.Message)" }
}
function Edit-Names {
  if ($root -eq $null) { return @() }
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
  return @($all | ForEach-Object { $_.Current.Name })
}
function Delete-Near([string]$editName) {
  # The Delete button on the same row as the named edit: nearest by vertical centre.
  $row = Edit $editName 15000
  if ($row -eq $null) { return $null }
  $ry = $row.Current.BoundingRectangle.Top + $row.Current.BoundingRectangle.Height / 2
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
  $best = $null; $bestDy = [double]::MaxValue
  foreach ($b in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
    if ($b.Current.Name -ne 'Delete') { continue }
    $by = $b.Current.BoundingRectangle.Top + $b.Current.BoundingRectangle.Height / 2
    $dy = [math]::Abs($by - $ry)
    if ($dy -lt $bestDy) { $bestDy = $dy; $best = $b }
  }
  Log "delete_near[$editName] dy=$([math]::Round($bestDy,1))"
  return $best
}
function Set-ClientDip([int]$w, [int]$h) {
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
  $ok = [SW.N]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
  Log "close_window=WM_CLOSE posted=$ok"
}

if ($root -ne $null) {
  switch ($Fixture) {
    'F1' {
      Focus-Edit 'Row 5'
      Log "focused_after_focus=[$(Focused-Name)]"
      Type-Key 0x41; Type-Key 0x42; Type-Key 0x43
      Wait-Value 'Row 5' 'Row 5abc' | Out-Null
      Wait-Element { Edit 'Row 99' } 'inserted row 99 (Engine 0)' 30000 | Out-Null
      Type-Key 0x44
      Wait-Value 'Row 5' 'Row 5abcd' | Out-Null
      Log "focused_final=[$(Focused-Name)]"
    }
    'F2' {
      Focus-Edit 'Row 3'
      Type-Key 0xBD; Type-Key 0x58
      Wait-Value 'Row 3' 'Row 3-x' | Out-Null
      Start-Sleep -Milliseconds 1200
      Log "uia_edit_order=[$((Edit-Names) -join ',')]"
      Log "focused_final=[$(Focused-Name)]"
    }
    'F3' {
      Focus-Edit 'Row 4'
      Type-Key 0x58
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
      Type-Key 0x4B; Type-Key 0x41
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
  Close-Window
} else {
  Log 'no window: UIA root unavailable'
}

if (-not $proc.WaitForExit(90000)) { $proc.Kill(); Log 'TIMEOUT: killed after 90 s' }
$proc.WaitForExit()
Log "exit=$($proc.ExitCode) end=$(Get-Date -Format o)"
Log '--- stdout ---'
Log ([string]$stdout.Result)
Log '--- stderr ---'
Log ([string]$stderr.Result)
[System.IO.File]::WriteAllText($Out, [string]::Join("`r`n", $lines))
