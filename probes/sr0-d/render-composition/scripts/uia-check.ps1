# SR0-D: launch the composition probe in the interactive desktop session and record what UI Automation sees.
# Run from an interactive PowerShell on the Windows host (not over SSH; UIA needs the desktop session).
param(
  [string]$Exe = 'D:\.rightkit-managed\rightkit-build-control\ws\9bf7012b2022\g\001\target\x86_64-pc-windows-msvc\release\sr0d-render-composition.exe',
  [string]$OutDir = 'D:\Claude\sr0d-uia'
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type -Namespace W -Name U -MemberDefinition '[DllImport("user32.dll")] public static extern bool IsWindowVisible(System.IntPtr h);'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$log = Join-Path $OutDir 'stderr.log'
$result = [ordered]@{ exe = $Exe; exeWriteTime = (Get-Item $Exe).LastWriteTime.ToString('o'); started = (Get-Date).ToString('o') }

$p = Start-Process -FilePath $Exe -PassThru -RedirectStandardError $log -RedirectStandardOutput (Join-Path $OutDir 'stdout.log') -WindowStyle Normal
$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 60 -and $hwnd -eq [IntPtr]::Zero; $i++) {
  Start-Sleep -Milliseconds 250; $p.Refresh()
  if ($p.HasExited) { break }
  $hwnd = $p.MainWindowHandle
}
$result.exitedEarly = $p.HasExited
if ($p.HasExited) { $result.exitCode = $p.ExitCode }
$result.hwnd = $hwnd.ToInt64()
if ($hwnd -ne [IntPtr]::Zero) {
  Start-Sleep -Seconds 2
  $result.windowVisible = [W.U]::IsWindowVisible($hwnd)
  $root = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
  $walker = [System.Windows.Automation.TreeWalker]::RawViewWalker
  $nodes = New-Object System.Collections.ArrayList
  function Walk($el, $depth) {
    if ($depth -gt 6) { return }
    $c = $el.Current
    $pats = ($el.GetSupportedPatterns() | ForEach-Object { $_.ProgrammaticName }) -join ','
    [void]$nodes.Add([ordered]@{ depth = $depth; type = $c.ControlType.ProgrammaticName; name = $c.Name; bounds = "$($c.BoundingRectangle)"; focusable = $c.IsKeyboardFocusable; patterns = $pats })
    $ch = $walker.GetFirstChild($el)
    while ($ch -ne $null) { Walk $ch ($depth + 1); $ch = $walker.GetNextSibling($ch) }
  }
  Walk $root 0
  $result.tree = $nodes
  $cond = { param($n) New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $n) }
  $btn = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (& $cond 'Probe'))
  $result.buttonFound = $btn -ne $null
  if ($btn) { try { $btn.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke(); $result.invoke = 'called' } catch { $result.invoke = "error: $($_.Exception.Message)" } }
  $inp = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (& $cond 'Probe input'))
  $result.inputFound = $inp -ne $null
  if ($inp) {
    try { $inp.SetFocus(); $result.focus = 'called' } catch { $result.focus = "error: $($_.Exception.Message)" }
    try { $inp.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue('hello'); $result.setValue = 'called' } catch { $result.setValue = "error: $($_.Exception.Message)" }
  }
  Start-Sleep -Seconds 1
}
if (-not $p.HasExited) { Stop-Process -Id $p.Id -Force }
Start-Sleep -Milliseconds 500
$result.stderr = if (Test-Path $log) { [string](Get-Content -Raw $log) } else { '' }
$result | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $OutDir 'result.json')
"Done. Result: $(Join-Path $OutDir 'result.json')"
