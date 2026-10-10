# Harness diagnostic (phase 2, once): why does UI Automation show no MenuItem under the host's #32768 popup window?
# Starts Modal06, waits for the S1 menu, dumps what UIA returns for several lookups, then kills the host. No input sent.
param([string]$Base = 'D:\Claude\sr0-geomodal', [string]$Out = 'D:\Claude\sr0-geomodal\probe-menu-uia.txt')
. (Join-Path $PSScriptRoot 'common.ps1')
$bin = Join-Path $Base 'bin'
$lines = New-Object System.Collections.Generic.List[string]
function L([string]$s) { $lines.Add($s) }
$log = Join-Path $Base 'out\probe-host.log'
Remove-Item $log -Force -ErrorAction SilentlyContinue
$hp = Start-Host (Join-Path $bin 'Modal06.exe') $bin @{ SWR_GM_LOG = $log; SWR_GM_TIMEOUT = '30' }
$proc = $hp.Proc
$main = Wait-MainWindow $proc 30
$mw = [IntPtr]::Zero
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 12 -and $mw -eq [IntPtr]::Zero) {
  foreach ($h in [GMWin]::TopLevel([uint32]$proc.Id)) { if ([GMWin]::IsWindowVisible($h) -and [GMWin]::ClassOf($h) -eq '#32768') { $mw = $h } }
  if ($mw -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 25 }
}
L "menu hwnd=$($mw.ToInt64()) class=$(if ($mw -ne [IntPtr]::Zero) { [GMWin]::ClassOf($mw) })"
if ($mw -ne [IntPtr]::Zero) {
  Start-Sleep -Milliseconds 600
  $AE = [System.Windows.Automation.AutomationElement]; $TS = [System.Windows.Automation.TreeScope]
  function Dump($el, [string]$tag, $scope) {
    try {
      $all = $el.FindAll($scope, [System.Windows.Automation.Condition]::TrueCondition)
      L "$tag count=$($all.Count)"
      $i = 0
      foreach ($e in $all) { if ($i++ -ge 30) { break }; L ("  {0} type={1} name=[{2}] class={3} enabled={4} fw={5} hwnd={6}" -f $i, $e.Current.ControlType.ProgrammaticName, $e.Current.Name, $e.Current.ClassName, $e.Current.IsEnabled, $e.Current.FrameworkId, $e.Current.NativeWindowHandle) }
    } catch { L "$tag ERR $($_.Exception.Message)" }
  }
  try {
    $el = $AE::FromHandle($mw)
    L ("FromHandle: type={0} name=[{1}] class={2} fw={3} rect={4}" -f $el.Current.ControlType.ProgrammaticName, $el.Current.Name, $el.Current.ClassName, $el.Current.FrameworkId, $el.Current.BoundingRectangle)
    Dump $el 'A FromHandle.Children' $TS::Children
    Dump $el 'B FromHandle.Subtree' $TS::Subtree
    $r = $el.Current.BoundingRectangle
    if (-not $r.IsEmpty) {
      $pt = New-Object System.Windows.Point(($r.X + 20), ($r.Y + 15))
      $fp = $AE::FromPoint($pt)
      L ("C FromPoint({0},{1}): type={2} name=[{3}] class={4} pid={5}" -f $pt.X, $pt.Y, $fp.Current.ControlType.ProgrammaticName, $fp.Current.Name, $fp.Current.ClassName, $fp.Current.ProcessId)
      Dump $fp 'C2 FromPoint.Children' $TS::Children
      $par = [System.Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($fp)
      if ($par) { L ("C3 parent: type={0} class={1}" -f $par.Current.ControlType.ProgrammaticName, $par.Current.ClassName) }
    }
    $pc = New-Object System.Windows.Automation.PropertyCondition($AE::ProcessIdProperty, [int]$proc.Id)
    $top = $AE::RootElement.FindAll($TS::Children, $pc)
    L "D root children of host pid: $($top.Count)"
    foreach ($t in $top) { L ("  top type={0} name=[{1}] class={2} hwnd={3}" -f $t.Current.ControlType.ProgrammaticName, $t.Current.Name, $t.Current.ClassName, $t.Current.NativeWindowHandle) }
    $mi = $AE::RootElement.FindAll($TS::Descendants, (New-Object System.Windows.Automation.AndCondition($pc, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem)))))
    L "E desktop-wide MenuItems of host pid: $($mi.Count)"
    foreach ($m in $mi) { L ("  mi name=[{0}] enabled={1}" -f $m.Current.Name, $m.Current.IsEnabled) }
  } catch { L "ERR $($_.Exception.Message)" }
}
$ms = Get-MsaaItems $mw
L "F MSAA items=$(@($ms.Items).Count) acc=$($ms.Acc -ne $null) $($ms.Debug)"
foreach ($it in @($ms.Items)) { L ("  msaa {0} name=[{1}] role={2} state=0x{3:X} enabled={4} checked={5}" -f $it.Index, $it.Name, $it.Role, $it.State, $it.Enabled, $it.Checked) }
try { $proc.Kill() } catch { }
[System.IO.File]::WriteAllText($Out, [string]::Join("`r`n", $lines))
