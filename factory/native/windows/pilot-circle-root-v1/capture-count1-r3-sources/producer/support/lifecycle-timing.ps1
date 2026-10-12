# Observations only; same retained kernel handle, zero-time queries, no waits/termination.
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class FactoryLifecycleTimingV1 {
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr h,uint ms);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern bool GetExitCodeProcess(IntPtr h,out uint exitCode);
 [DllImport("kernel32.dll",SetLastError=true)] public static extern uint GetProcessId(IntPtr h);
 [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
}
'@
function Get-FactoryLifecycleTimingSample([string]$Phase,$Process,[IntPtr]$RetainedHandle,$RawStreams) {
 $row=[ordered]@{phase=$Phase;systemTickMS=[FactoryLifecycleTimingV1]::GetTickCount64();utc=[DateTimeOffset]::UtcNow.ToString('o');frequency=[Diagnostics.Stopwatch]::Frequency;queryStartTicks=[Diagnostics.Stopwatch]::GetTimestamp();retainedHandle=$RetainedHandle.ToInt64();kernelBefore=$null;kernelAfter=$null;handlePid=$null;hasExited=$null;hasExitedStartTicks=$null;hasExitedEndTicks=$null;getExitCodeSucceeded=$null;exitCode=$null;getExitCodeError=$null;errors=@();rawStreams=@()}
 try{$row.kernelBefore=[FactoryLifecycleTimingV1]::WaitForSingleObject($RetainedHandle,0);$row.handlePid=[FactoryLifecycleTimingV1]::GetProcessId($RetainedHandle)}catch{$row.errors+=('kernel-before: '+[string]$_)}
 $row.hasExitedStartTicks=[Diagnostics.Stopwatch]::GetTimestamp()
 try{$row.hasExited=[bool]$Process.HasExited}catch{$row.errors+=('HasExited: '+[string]$_)}
 $row.hasExitedEndTicks=[Diagnostics.Stopwatch]::GetTimestamp()
 try{$exit=[uint32]0;$row.getExitCodeSucceeded=[FactoryLifecycleTimingV1]::GetExitCodeProcess($RetainedHandle,[ref]$exit);$row.getExitCodeError=[Runtime.InteropServices.Marshal]::GetLastWin32Error();if($row.getExitCodeSucceeded){$row.exitCode=$exit}}catch{$row.errors+=('GetExitCodeProcess: '+[string]$_)}
 try{$row.kernelAfter=[FactoryLifecycleTimingV1]::WaitForSingleObject($RetainedHandle,0)}catch{$row.errors+=('kernel-after: '+[string]$_)}
 try{$stateJSON=@($RawStreams|ForEach-Object{Get-FactoryRawStreamState $_})|ConvertTo-Json -Depth 12;$decodedStates=$stateJSON|ConvertFrom-Json;$row.rawStreams=@($decodedStates)}catch{$row.errors+=('raw-state: '+[string]$_)}
 $row.queryEndTicks=[Diagnostics.Stopwatch]::GetTimestamp()
 return $row
}
