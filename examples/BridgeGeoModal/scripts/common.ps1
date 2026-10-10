# Shared helpers of the BridgeGeoModal drivers (dot-sourced by drive-textgeom.ps1, drive-modal.ps1, dryrun.ps1).
# Input policy (SR0 rule): NEVER a global keystroke or mouse event. The drivers only use UI Automation and
# PostMessage to windows owned by the host process under test (its main window, its popup menu, its task dialog).
$ErrorActionPreference = 'Continue'
$script:SwiftRuntime = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'
$script:PinnedRendererSha = '7533963d124c066159322edf540bd45637cc294173fd9db2af95d4d4a3f149fc'

Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, Accessibility
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class GMWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassNameW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextW(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  [DllImport("user32.dll")] public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code, uint type);
  [DllImport("oleacc.dll")] public static extern int AccessibleObjectFromWindow(IntPtr hwnd, uint objectId, ref Guid riid, out IntPtr ppv);
  public static string ClassOf(IntPtr h) { var sb = new StringBuilder(256); GetClassNameW(h, sb, 256); return sb.ToString(); }
  public static string TitleOf(IntPtr h) { var sb = new StringBuilder(512); GetWindowTextW(h, sb, 512); return sb.ToString(); }
  public static IntPtr[] TopLevel(uint pid) {
    var list = new List<IntPtr>();
    EnumWindows(delegate(IntPtr h, IntPtr l) { uint p; GetWindowThreadProcessId(h, out p); if (p == pid) list.Add(h); return true; }, IntPtr.Zero);
    return list.ToArray();
  }
}
'@

# per-monitor v2: UIA and ClientToScreen then report physical pixels, like the host's commit coordinates
$null = [GMWin]::SetProcessDpiAwarenessContext([IntPtr]::new(-4))

function Get-Sha([string]$Path) { (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower() }

# Reads a file another process is appending to (the host flushes every line).
function Read-Shared([string]$Path) {
  try {
    $fs = [System.IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
    $t = $sr.ReadToEnd(); $sr.Close(); $fs.Close(); return $t
  } catch { return '' }
}

# Polls the host log until a line matches the regex (multiline) or the time is up; returns the whole log either way.
function Wait-Log([string]$Path, [string]$Pattern, [double]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $t = Read-Shared $Path
    if ($t -match "(?m)$Pattern") { return $t }
    Start-Sleep -Milliseconds 40
  }
  return (Read-Shared $Path)
}

function Unesc([string]$s) {
  return [regex]::Replace($s, '\\(.)', { param($m) if ($m.Groups[1].Value -eq 'n') { "`n" } else { $m.Groups[1].Value } })
}

# Starts a host exe with the environment overrides; stdout/stderr are collected asynchronously.
function Start-Host([string]$Exe, [string]$Bin, [hashtable]$EnvVars) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $Exe
  $psi.WorkingDirectory = $Bin
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.EnvironmentVariables['Path'] = "$($script:SwiftRuntime);$Bin;" + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  foreach ($k in $EnvVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$EnvVars[$k] }
  $p = [System.Diagnostics.Process]::Start($psi)
  return [pscustomobject]@{ Proc = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}

function Wait-MainWindow($Proc, [double]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    $Proc.Refresh()
    if ($Proc.HasExited) { return [IntPtr]::Zero }
    $h = $Proc.MainWindowHandle
    if ($h -ne [IntPtr]::Zero) { return $h }
    Start-Sleep -Milliseconds 100
  }
  return [IntPtr]::Zero
}

function Write-Result([string]$Path, [string[]]$Lines) {
  [System.IO.File]::WriteAllText($Path, ([string]::Join("`r`n", $Lines) + "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
}

function Get-Artifacts([string]$Bin, [string[]]$Exes) {
  $parts = @()
  foreach ($e in $Exes) { $parts += ("{0}={1}" -f $e, (Get-Sha (Join-Path $Bin $e))) }
  $parts += ("renderer={0}" -f (Get-Sha (Join-Path $Bin 'swiftright_render.dll')))
  return 'ARTIFACTS ' + ($parts -join ' ')
}

function Test-ParseFile([string]$Path) {
  $errs = $null; $tokens = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errs)
  return ,@($errs)
}

# MSAA (IAccessible) children of a window's client object. UI Automation shows the classic #32768 popup menu as one empty Pane
# (probe-menu-uia.ps1, 10 Oct), but its items are reachable through MSAA: name, state (UNAVAILABLE = disabled, CHECKED) and
# accDoDefaultAction. Returns the IAccessible and the items.
function Get-MsaaItems([IntPtr]$Hwnd) {
  $items = @()
  $acc = $null
  $dbg = ''
  try {
    $g = [Guid]'618736E0-3C3D-11CF-810C-00AA00389B71'
    $ptr = [IntPtr]::Zero
    $hr = [GMWin]::AccessibleObjectFromWindow($Hwnd, [uint32]4294967292, [ref]$g, [ref]$ptr)     # OBJID_CLIENT = -4
    $dbg = "hr=0x{0:X} ptr={1}" -f $hr, $ptr.ToInt64()
    if ($hr -eq 0 -and $ptr -ne [IntPtr]::Zero) {
      $o = [System.Runtime.InteropServices.Marshal]::GetObjectForIUnknown($ptr)
      $acc = $o      # late-bound IDispatch (a cast to Accessibility.IAccessible fails in Windows PowerShell)
      $n = [int]$acc.accChildCount
      $dbg += " children=$n"
      for ($i = 1; $i -le $n; $i++) {
        $name = $acc.accName($i); $state = [int]$acc.accState($i); $role = [int]$acc.accRole($i)
        $items += [pscustomobject]@{ Index = $i; Name = [string]$name; State = $state; Role = $role; Enabled = (($state -band 0x1) -eq 0); Checked = (($state -band 0x10) -ne 0) }
      }
    }
  } catch { $dbg += " ERR $($_.Exception.Message)" }
  return [pscustomobject]@{ Acc = $acc; Items = $items; Debug = $dbg }
}
