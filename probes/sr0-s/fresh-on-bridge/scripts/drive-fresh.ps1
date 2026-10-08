# Drives FreshOnBridge.exe --self-test from INSIDE an interactive desktop session (one-shot task):
#  - launches the exe, waits for its window, brings it to the foreground
#  - UIA focus on the "Row 5" edit (AX focus action), then VK a, b, c (virtual keys, never Unicode packets)
#  - UIA Invoke on "Insert above"; the exe releases the fake engine itself (self-test step)
#  - reads UIA Value of row 5 and the focused element after the insert, then VK d
#  - waits for the exe; writes the driver lines plus the exe's stdout/stderr to $Out
param(
  [string]$Base = 'D:\Claude\sr0s-bridge',
  [string]$Out = 'D:\Claude\sr0s-bridge\result-fresh-run1.txt'
)
$ErrorActionPreference = 'Continue'
$Bin = "$Base\scratch\out\Products\Release-windows-x86_64"
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -Namespace SW -Name N -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
'@
$lines = New-Object System.Collections.Generic.List[string]
function Log([string]$s) { $lines.Add($s) }
if (-not [SW.N]::SetProcessDpiAwarenessContext([IntPtr]-4)) { [void][SW.N]::SetProcessDPIAware() }
Log "host=$env:COMPUTERNAME user=$env:USERNAME session=$((Get-Process -Id $PID).SessionId) started=$(Get-Date -Format o)"

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = Join-Path $Bin 'FreshOnBridge.exe'
$psi.Arguments = '--self-test'
$psi.WorkingDirectory = $Bin
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.EnvironmentVariables['Path'] = "C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
$proc = [System.Diagnostics.Process]::Start($psi)
$stdout = $proc.StandardOutput.ReadToEndAsync()
$stderr = $proc.StandardError.ReadToEndAsync()

$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 120 -and $hwnd -eq [IntPtr]::Zero -and -not $proc.HasExited; $i++) {
  Start-Sleep -Milliseconds 250; $proc.Refresh(); $hwnd = $proc.MainWindowHandle
}
Log "window_hwnd=$($hwnd.ToInt64()) polls=$i exited_early=$($proc.HasExited)"

function Find-Named([System.Windows.Automation.AutomationElement]$root, [string]$name, $type) {
  $cond = New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name)),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $type)))
  for ($k = 0; $k -lt 60; $k++) {
    $el = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    if ($el -ne $null) { return $el }
    Start-Sleep -Milliseconds 250
  }
  return $null
}
function Value-Of($el) {
  if ($el -eq $null) { return 'NOT_FOUND' }
  try { return $el.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { return "ERR $($_.Exception.Message)" }
}
function Focused-Name {
  try { return [System.Windows.Automation.AutomationElement]::FocusedElement.Current.Name } catch { return "ERR $($_.Exception.Message)" }
}
function Type-Key([byte]$vk) {
  [SW.N]::SetForegroundWindow($hwnd) | Out-Null
  [SW.N]::keybd_event($vk, 0, 0, [UIntPtr]::Zero); Start-Sleep -Milliseconds 60
  [SW.N]::keybd_event($vk, 0, 2, [UIntPtr]::Zero); Start-Sleep -Milliseconds 200
}

if ($hwnd -ne [IntPtr]::Zero) {
  Start-Sleep -Milliseconds 1500
  [void][SW.N]::SetForegroundWindow($hwnd)
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)

  $row5 = Find-Named $root 'Row 5' ([System.Windows.Automation.ControlType]::Edit)
  if ($row5 -eq $null) { Log 'uia_row5=NOT_FOUND' } else {
    try { $row5.SetFocus(); Log 'uia_focus_row5=ok' } catch { Log "uia_focus_row5=ERR $($_.Exception.Message)" }
  }
  Start-Sleep -Milliseconds 800
  Log "focused_after_uia_focus=[$(Focused-Name)]"

  Type-Key 0x41; Type-Key 0x42; Type-Key 0x43
  Start-Sleep -Milliseconds 800
  Log "row5_value_after_abc=[$(Value-Of $row5)]"

  $insert = Find-Named $root 'Insert above' ([System.Windows.Automation.ControlType]::Button)
  if ($insert -eq $null) { Log 'uia_insert=NOT_FOUND' } else {
    try { $insert.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); Log 'uia_invoke_insert_above=ok' } catch { Log "uia_invoke_insert_above=ERR $($_.Exception.Message)" }
  }
  Start-Sleep -Milliseconds 2000

  $row5b = Find-Named $root 'Row 5' ([System.Windows.Automation.ControlType]::Edit)
  Log "row5_value_after_insert=[$(Value-Of $row5b)]"
  Log "focused_after_insert=[$(Focused-Name)]"

  Type-Key 0x44
  Start-Sleep -Milliseconds 1200
  $row5c = Find-Named $root 'Row 5' ([System.Windows.Automation.ControlType]::Edit)
  Log "row5_value_final=[$(Value-Of $row5c)]"
  Log "focused_final=[$(Focused-Name)]"
  try {
    Add-Type -AssemblyName System.Drawing
    $r = $root.Current.BoundingRectangle
    $bmp = New-Object System.Drawing.Bitmap ([int]$r.Width), ([int]$r.Height)
    $gfx = [System.Drawing.Graphics]::FromImage($bmp)
    $gfx.CopyFromScreen([int]$r.X, [int]$r.Y, 0, 0, $bmp.Size)
    $w = 800; $h = [int](800 * $bmp.Height / $bmp.Width)
    $small = New-Object System.Drawing.Bitmap $w, $h
    $g2 = [System.Drawing.Graphics]::FromImage($small)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g2.DrawImage($bmp, 0, 0, $w, $h)
    $shot = [System.IO.Path]::ChangeExtension($Out, '.png')
    $small.Save($shot, [System.Drawing.Imaging.ImageFormat]::Png)
    Log "screenshot=$shot size=$($bmp.Width)x$($bmp.Height) scaled_to=${w}x${h}"
  } catch { Log "screenshot=ERR $($_.Exception.Message)" }
}

if (-not $proc.WaitForExit(90000)) { $proc.Kill(); Log 'TIMEOUT: killed after 90 s' }
$proc.WaitForExit()
Log "exit=$($proc.ExitCode) end=$(Get-Date -Format o)"
Log '--- stdout ---'
Log ([string]$stdout.Result)
Log '--- stderr ---'
Log ([string]$stderr.Result)
[System.IO.File]::WriteAllText($Out, [string]::Join("`r`n", $lines))
