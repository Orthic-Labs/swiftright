# SR0 tuple12 v3 source-only Windows job lifecycle controls.
# Root runs one mode at a time on Dell; this file never touches desktop lock, GUI, input, or Git.
[CmdletBinding()]
param(
  [ValidateSet('positive','wrong-memory-flag','resume-before-assignment','drop-active-query')]
  [string]$Mode = 'positive',
  [string]$ChildPath = "$env:WINDIR\System32\cmd.exe"
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $ChildPath -PathType Leaf)) { throw "child missing: $ChildPath" }
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class Sr0JobControlV1 {
  const uint CREATE_SUSPENDED=4, CREATE_NO_WINDOW=0x08000000, CREATE_UNICODE_ENVIRONMENT=0x400;
  [StructLayout(LayoutKind.Sequential, Pack=8)] public struct Basic { public long perProcessUserTime; public long perJobUserTime; public uint flags; public UIntPtr minimumWorkingSet; public UIntPtr maximumWorkingSet; public uint activeProcessLimit; public UIntPtr affinity; public uint priorityClass; public uint schedulingClass; }
  [StructLayout(LayoutKind.Sequential, Pack=8)] public struct Io { public ulong read; public ulong write; public ulong other; public ulong readBytes; public ulong writeBytes; public ulong otherBytes; }
  [StructLayout(LayoutKind.Sequential, Pack=8)] public struct Extended { public Basic basic; public Io io; public UIntPtr processMemory; public UIntPtr jobMemory; public UIntPtr peakProcess; public UIntPtr peakJob; }
  [StructLayout(LayoutKind.Sequential)] public struct Accounting { public long totalUser; public long totalKernel; public long periodUser; public long periodKernel; public uint pageFaults; public uint totalProcesses; public uint activeProcesses; public uint totalTerminated; }
  [StructLayout(LayoutKind.Sequential)] public struct PI { public IntPtr process; public IntPtr thread; public uint processId; public uint threadId; }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObject(IntPtr attrs, string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, int kind, ref Extended info, uint length);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job, int kind, IntPtr info, uint length, out uint returned);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern bool CreateProcess(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, IntPtr si, out PI pi);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern uint ResumeThread(IntPtr thread);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateProcess(IntPtr p, uint code);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
  public static IntPtr CreateJob() { return CreateJobObject(IntPtr.Zero, null); }
  public static bool Configure(IntPtr job, bool wrong) { var x=new Extended(); x.basic.flags=0x2000u | (wrong ? 0x100u : 0x200u); x.jobMemory=(UIntPtr)1073741824UL; return SetInformationJobObject(job,9,ref x,(uint)Marshal.SizeOf(typeof(Extended))); }
  public static bool ReadFlags(IntPtr job, out uint flags) { flags=0; int n=Marshal.SizeOf(typeof(Extended)); IntPtr p=Marshal.AllocHGlobal(n); try { uint got; if(!QueryInformationJobObject(job,9,p,(uint)n,out got)) return false; flags=((Extended)Marshal.PtrToStructure(p,typeof(Extended))).basic.flags; return true; } finally { Marshal.FreeHGlobal(p); } }
  public static bool ReadActive(IntPtr job, out uint active) { active=0; int n=Marshal.SizeOf(typeof(Accounting)); IntPtr p=Marshal.AllocHGlobal(n); try { uint got; if(!QueryInformationJobObject(job,1,p,(uint)n,out got)) return false; active=((Accounting)Marshal.PtrToStructure(p,typeof(Accounting))).activeProcesses; return true; } finally { Marshal.FreeHGlobal(p); } }
  public static bool StartSuspended(string app, out IntPtr process, out IntPtr thread) { process=IntPtr.Zero; thread=IntPtr.Zero; var pi=new PI(); var cmd=new StringBuilder("cmd.exe /d /c exit 0"); if(!CreateProcess(app,cmd,IntPtr.Zero,IntPtr.Zero,false,CREATE_SUSPENDED|CREATE_NO_WINDOW|CREATE_UNICODE_ENVIRONMENT,IntPtr.Zero,null,IntPtr.Zero,out pi)) return false; process=pi.process; thread=pi.thread; return true; }
}
'@
$job = [Sr0JobControlV1]::CreateJob()
$process = [IntPtr]::Zero; $thread = [IntPtr]::Zero; $assigned = $false; $terminal = $false
try {
  if ($job -eq [IntPtr]::Zero) { throw 'CreateJobObject failed' }
  $configured = [Sr0JobControlV1]::Configure($job, $Mode -eq 'wrong-memory-flag')
  if (-not $configured) { throw 'SetInformationJobObject failed' }
  $flags = [uint32]0
  if (-not [Sr0JobControlV1]::ReadFlags($job, [ref]$flags)) { throw 'job limits query failed' }
  if ($Mode -eq 'wrong-memory-flag') {
    if (($flags -band 0x100u) -eq 0) { throw 'fault control did not preserve wrong flag' }
    if (($flags -band 0x200u) -ne 0) { throw 'wrong memory fault unexpectedly has job-memory flag' }
  } elseif (($flags -band 0x2000u) -eq 0 -or ($flags -band 0x200u) -eq 0) {
    throw "required job flags missing: $flags"
  }
  if (-not [Sr0JobControlV1]::StartSuspended($ChildPath, [ref]$process, [ref]$thread)) { throw 'CreateProcess suspended failed' }
  if ($Mode -eq 'resume-before-assignment') {
    if ([Sr0JobControlV1]::ResumeThread($thread) -eq [uint32]0xffffffff) { throw 'fault setup resume failed' }
    $assigned = [Sr0JobControlV1]::AssignProcessToJobObject($job, $process)
    if ($assigned) { throw 'resume-before-assignment fault was accepted' }
    [Sr0JobControlV1]::TerminateProcess($process, 124) | Out-Null
  } else {
    if (-not [Sr0JobControlV1]::AssignProcessToJobObject($job, $process)) { throw 'job assignment failed' }
    $assigned = $true
    if ([Sr0JobControlV1]::ResumeThread($thread) -eq [uint32]0xffffffff) { throw 'resume failed' }
    if ([Sr0JobControlV1]::WaitForSingleObject($process, 5000) -ne 0) { throw 'child terminal wait failed' }
    $terminal = $true
    $code = [uint32]0
    if (-not [Sr0JobControlV1]::GetExitCodeProcess($process, [ref]$code) -or $code -eq 259) { throw 'child kernel exit proof failed' }
    if ($Mode -eq 'drop-active-query') { throw 'active-count omission fault was accepted' }
    $active = [uint32]0
    if (-not [Sr0JobControlV1]::ReadActive($job, [ref]$active)) { throw 'active-count query failed' }
    if ($active -ne 0) { throw "job not quiescent: $active" }
  }
  if ($Mode -eq 'positive') { 'job-control positive: PASS suspended->assign->resume, flags, kernel exit, active=0' }
  elseif ($Mode -eq 'wrong-memory-flag') { 'job-control wrong-memory-flag: PASS rejected per-process flag' }
  elseif ($Mode -eq 'resume-before-assignment') { 'job-control resume-before-assignment: PASS rejected escape order' }
  else { 'job-control drop-active-query: PASS omission rejected' }
} finally {
  if ($process -ne [IntPtr]::Zero -and -not $terminal) { [Sr0JobControlV1]::TerminateProcess($process, 124) | Out-Null; [Sr0JobControlV1]::WaitForSingleObject($process, 5000) | Out-Null }
  if ($thread -ne [IntPtr]::Zero) { [Sr0JobControlV1]::CloseHandle($thread) | Out-Null }
  if ($process -ne [IntPtr]::Zero) { [Sr0JobControlV1]::CloseHandle($process) | Out-Null }
  if ($job -ne [IntPtr]::Zero) { [Sr0JobControlV1]::CloseHandle($job) | Out-Null }
}
