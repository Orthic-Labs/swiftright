# Root integration envelope: owned PresentMon + direct frozen workload in one 1GiB self-job.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Base,
  [Parameter(Mandatory)][string]$ControlRoot,
  [Parameter(Mandatory)][string]$FrozenTaskPath,
  [Parameter(Mandatory)][string]$HelperPath,
  [Parameter(Mandatory)][string]$ParserPath,
  [Parameter(Mandatory)][string]$FrozenTaskSha256,
  [Parameter(Mandatory)][string]$HelperSha256,
  [Parameter(Mandatory)][string]$ParserSha256,
  [Parameter(Mandatory)][string]$RunRoot,
  [Parameter(Mandatory)][string]$ResultFile,
  [Parameter(Mandatory)][string]$MemoryReceiptPath,
  [Parameter(Mandatory)][string]$StartReceiptPath,
  [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$TaskName,
  [Parameter(Mandatory)][string]$PresentMonExe,
  [Parameter(Mandatory)][string]$PresentMonSha256,
  [string]$Lock='D:\Claude\desktop.lock',
  [string]$Tag='sr0-display-selfjob-v4',
  [ValidateRange(1,20)][int]$Runs=1,
  [ValidateRange(1,120)][int]$Warmup=10,
  [ValidateRange(1,300)][int]$Measure=60,
  [int]$Rows=200,
  [double]$KeyRate=10,
  [switch]$NoResources,
  [Parameter(Mandatory)][switch]$NoActivate,
  [int64]$MaxCsvBytes=67108864,
  [int64]$MaxStdoutBytes=8388608,
  [int64]$MaxStderrBytes=8388608,
  [int]$DeadlineSeconds=900,
  [int]$PollSeconds=1
)
$ErrorActionPreference='Stop'
$sha='^[0-9a-fA-F]{64}$'
if($FrozenTaskSha256 -notmatch $sha -or $HelperSha256 -notmatch $sha -or $ParserSha256 -notmatch $sha -or $PresentMonSha256 -notmatch $sha){throw 'explicit source pins must be SHA-256'}
if($PollSeconds -lt 1 -or $DeadlineSeconds -lt 1){throw 'invalid bounded collector timing'}
foreach($p in @($Base,$ControlRoot)){if(-not(Test-Path -LiteralPath $p -PathType Container)){throw "required directory missing: $p"}}
foreach($p in @($FrozenTaskPath,$HelperPath,$ParserPath,$PresentMonExe)){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "required source missing: $p"}}
$baseFull=[IO.Path]::GetFullPath($Base);$controlFull=[IO.Path]::GetFullPath($ControlRoot);$frozenFull=[IO.Path]::GetFullPath($FrozenTaskPath);$helperFull=[IO.Path]::GetFullPath($HelperPath);$parserFull=[IO.Path]::GetFullPath($ParserPath);$pmFull=[IO.Path]::GetFullPath($PresentMonExe);$runFull=[IO.Path]::GetFullPath($RunRoot);$resultFull=[IO.Path]::GetFullPath($ResultFile);$memoryFull=[IO.Path]::GetFullPath($MemoryReceiptPath);$startFull=[IO.Path]::GetFullPath($StartReceiptPath);$lockFull=[IO.Path]::GetFullPath($Lock)
foreach($p in @($frozenFull,$helperFull,$parserFull,$pmFull)){if(((Get-Item -LiteralPath $p).Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw "source reparse point rejected: $p"}}
if((Test-Path -LiteralPath $memoryFull) -or (Test-Path -LiteralPath $startFull)){throw 'memory/start receipt must be fresh'}
$frozenObserved=(Get-FileHash -LiteralPath $frozenFull -Algorithm SHA256).Hash.ToLowerInvariant();$helperObserved=(Get-FileHash -LiteralPath $helperFull -Algorithm SHA256).Hash.ToLowerInvariant();$parserObserved=(Get-FileHash -LiteralPath $parserFull -Algorithm SHA256).Hash.ToLowerInvariant();$pmObserved=(Get-FileHash -LiteralPath $pmFull -Algorithm SHA256).Hash.ToLowerInvariant();if($frozenObserved -cne $FrozenTaskSha256.ToLowerInvariant() -or $helperObserved -cne $HelperSha256.ToLowerInvariant() -or $parserObserved -cne $ParserSha256.ToLowerInvariant() -or $pmObserved -cne $PresentMonSha256.ToLowerInvariant()){throw 'pinned source hash mismatch'}
[IO.Directory]::CreateDirectory($runFull)|Out-Null
foreach($p in @((Split-Path -Parent $resultFull),(Split-Path -Parent $memoryFull),(Split-Path -Parent $startFull))){if(-not(Test-Path -LiteralPath $p)){[IO.Directory]::CreateDirectory($p)|Out-Null}}
Add-Type -Path $helperFull
. $parserFull
Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using System.Runtime.InteropServices;
public sealed class Sr0DisplayDrainStateV4 { public long Bytes; public int Exceeded; }
public sealed class Sr0DisplayDrainResultV4 { public long Bytes; public bool Exceeded; public string Path; }
public static class Sr0DisplayDrainV4 {
  public static Task<Sr0DisplayDrainResultV4> Start(StreamReader reader, long cap, string path, Sr0DisplayDrainStateV4 state) {
    return Task.Run(() => {
      using(var fs=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.Read)) {
        var chars=new char[4096]; long bytes=0; bool exceeded=false; int n;
        while((n=reader.Read(chars,0,chars.Length))>0) {
          var encoded=Encoding.UTF8.GetBytes(chars,0,n); long part=encoded.LongLength; bytes += part;
          System.Threading.Interlocked.Add(ref state.Bytes,part);
          if(bytes <= cap) fs.Write(encoded,0,encoded.Length); else { exceeded=true; System.Threading.Interlocked.Exchange(ref state.Exceeded,1); long prior=bytes-part; long keep=cap-prior; if(keep>0) fs.Write(encoded,0,(int)Math.Min(keep,encoded.Length)); }
        }
        fs.Flush(true);
        return new Sr0DisplayDrainResultV4 { Bytes=bytes, Exceeded=exceeded, Path=path };
      }
    });
  }
  public static long SnapshotBytes(Sr0DisplayDrainStateV4 state) { return System.Threading.Interlocked.Read(ref state.Bytes); }
  public static bool IsExceeded(Sr0DisplayDrainStateV4 state) { return System.Threading.Interlocked.CompareExchange(ref state.Exceeded,0,0)!=0; }
}
public static class Sr0DisplayProcessV4 {
  [DllImport("kernel32.dll",EntryPoint="WaitForSingleObject",SetLastError=true)] static extern uint WaitForSingleObject(IntPtr h,uint ms);
  [DllImport("kernel32.dll",EntryPoint="GetExitCodeProcess",SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr h,out uint code);
  public static bool Terminal(IntPtr h,out uint code) { code=259; if(h==IntPtr.Zero)return false; if(WaitForSingleObject(h,0)!=0)return false; if(!GetExitCodeProcess(h,out code))return false; return code!=259; }
  public static long SignedDword(uint code) { return unchecked((int)code); }
}
public static class Sr0DisplaySessionV4 {
  [DllImport("kernel32.dll",EntryPoint="ProcessIdToSessionId",SetLastError=true)] static extern bool ProcessIdToSessionId(uint pid,out uint session);
  [DllImport("kernel32.dll",EntryPoint="WTSGetActiveConsoleSessionId")] static extern uint WTSGetActiveConsoleSessionId();
  public static bool MatchesActive(out uint current,out uint active){current=0;active=WTSGetActiveConsoleSessionId();return ProcessIdToSessionId((uint)Process.GetCurrentProcess().Id,out current)&&current==active;}
}
public sealed class Sr0DisplayDesktopProbeV4 { public bool Available,NameRead; public int LastError; public string Name; }
public static class Sr0DisplayDesktopV4 {
  private const uint DesktopReadObjects=0x0001; private const int UserObjectName=2;
  [DllImport("user32.dll",EntryPoint="OpenInputDesktop",SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
  [DllImport("user32.dll",EntryPoint="GetUserObjectInformationW",SetLastError=true,CharSet=CharSet.Unicode)] static extern bool GetUserObjectInformationW(IntPtr handle,int index,IntPtr info,uint length,out uint needed);
  [DllImport("user32.dll",EntryPoint="CloseDesktop",SetLastError=true)] static extern bool CloseDesktop(IntPtr handle);
  public static Sr0DisplayDesktopProbeV4 Probe(){var result=new Sr0DisplayDesktopProbeV4{Name=null,NameRead=false,Available=false,LastError=0};IntPtr desktop=OpenInputDesktop(0,false,DesktopReadObjects);if(desktop==IntPtr.Zero){result.LastError=Marshal.GetLastWin32Error();return result;}result.Available=true;IntPtr buffer=Marshal.AllocHGlobal(512);try{uint needed;result.NameRead=GetUserObjectInformationW(desktop,UserObjectName,buffer,512,out needed);if(result.NameRead){int chars=Math.Min(256,Math.Max(0,(int)needed/2));result.Name=Marshal.PtrToStringUni(buffer,chars).TrimEnd('\0');}else{result.LastError=Marshal.GetLastWin32Error();}}finally{Marshal.FreeHGlobal(buffer);CloseDesktop(desktop);}return result;}
}
'@
function Quote-Arg([string]$v){if($v -notmatch '[\s"]'){return $v};return '"'+$v.Replace('"','\"')+'"'}
function Start-Owned([string]$File,[string[]]$Arguments,[string]$WorkingDirectory){$psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=$File;$psi.Arguments=(($Arguments|ForEach-Object{Quote-Arg ([string]$_)}) -join ' ');$psi.WorkingDirectory=$WorkingDirectory;$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$p=[Diagnostics.Process]::Start($psi);if($null -eq $p){throw "process did not start: $File"};try{$h=$p.Handle;if($h -eq [IntPtr]::Zero){throw "process handle is null: $File"}}catch{try{if(-not $p.HasExited){$p.Kill()};[void]$p.WaitForExit(5000)}catch{};throw};return $p}
function Drain-Bytes($task){try{if($null -ne $task -and $task.IsCompleted){return $task.Result.Bytes}}catch{};return $null}
function Read-BoundedText([string]$path,[int64]$cap=1048576){if(-not(Test-Path -LiteralPath $path -PathType Leaf)){return ''};$length=(Get-Item -LiteralPath $path).Length;if($length -gt $cap){throw "bounded receipt read exceeded: $path"};return [IO.File]::ReadAllText($path)}
function Lock-Free([string]$text){if($text.Trim() -eq 'free'){return $true};try{$o=$text|ConvertFrom-Json;foreach($n in @('state','status','value')){if($o.PSObject.Properties.Name -contains $n -and [string]$o.$n -eq 'free'){return $true}}}catch{};return $false}
function Acquire-Lock([string]$owner){try{$s=[IO.File]::Open($lockFull,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{$sr=New-Object System.IO.StreamReader -ArgumentList @($s,[Text.Encoding]::UTF8,$true,1024,$true);$s.Position=0;$text=$sr.ReadToEnd();$sr.Dispose();if(-not(Lock-Free $text)){return $false};$s.SetLength(0);$s.Position=0;$b=[Text.Encoding]::UTF8.GetBytes("$owner`r`n");$s.Write($b,0,$b.Length);$s.Flush($true);return $true}finally{$s.Dispose()}}catch [IO.IOException]{return $false}}
function Release-Lock([string]$owner){$s=[IO.File]::Open($lockFull,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);try{$s.Position=0;$sr=New-Object System.IO.StreamReader -ArgumentList @($s,[Text.Encoding]::UTF8,$true,1024,$true);$current=$sr.ReadToEnd().Trim();$sr.Dispose();if($current -cne $owner){throw 'desktop lock ownership changed; preserving lock'};$s.Position=0;$b=[Text.Encoding]::UTF8.GetBytes("free`r`n");$s.SetLength(0);$s.Write($b,0,$b.Length);$s.Flush($true)}finally{$s.Dispose()}}
function Write-AtomicFresh([string]$Path,[string]$Text){if(Test-Path -LiteralPath $Path){throw "receipt must be fresh: $Path"};$tmp="$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp";if(Test-Path -LiteralPath $tmp){throw "receipt temp must be fresh: $tmp"};$s=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$b=[Text.Encoding]::UTF8.GetBytes($Text);$s.Write($b,0,$b.Length);$s.Flush($true)}finally{$s.Dispose()};[IO.File]::Move($tmp,$Path)}
$pmCsv=Join-Path $runFull 'presentmon.csv';$pmStdoutPath=Join-Path $runFull 'presentmon.stdout.txt';$pmStderrPath=Join-Path $runFull 'presentmon.stderr.txt';$workStdoutPath=Join-Path $runFull 'workload.stdout.txt';$workStderrPath=Join-Path $runFull 'workload.stderr.txt';$pmStopStdoutPath=Join-Path $runFull 'presentmon-stop.stdout.txt';$pmStopStderrPath=Join-Path $runFull 'presentmon-stop.stderr.txt';$pmQueryStdoutPath=Join-Path $runFull 'presentmon-query.stdout.txt';$pmQueryStderrPath=Join-Path $runFull 'presentmon-query.stderr.txt';$pmSession="SR0BWL-$Tag";$powershell=Join-Path $PSHOME 'powershell.exe';$lockOwner="SR0-DISPLAY-SELFJOB-$Tag"
$parentProcess=$null;$parentHandle=[IntPtr]::Zero;$parentHandleAcquired=$false;$parentPath=$null;$parentStartUtc=$null;$pm=$null;$pmHandleAcquired=$false;$pmStarted=$false;$pmStartObservedAt=$null;$workload=$null;$workloadHandleAcquired=$false;$pmStop=$null;$pmStopHandleAcquired=$false;$pmQuery=$null;$pmQueryHandleAcquired=$false;$pmStopOutTask=$null;$pmStopErrTask=$null;$pmQueryOutTask=$null;$pmQueryErrTask=$null;$pmStopExit=$null;$pmQueryExit=$null;$pmOutTask=$null;$pmErrTask=$null;$workOutTask=$null;$workErrTask=$null;$pmOutState=$null;$pmErrState=$null;$workOutState=$null;$workErrState=$null;$pmStopOutState=$null;$pmStopErrState=$null;$pmQueryOutState=$null;$pmQueryErrState=$null;$job=$null;$lockHeld=$false;$lockReleased=$false;$releaseAllowed=$false;$sessionMatch=$false;$desktopAvailable=$false;$desktopNameRead=$false;$desktopLastError=$null;$desktopName=$null;[uint32]$currentSession=0;[uint32]$activeConsoleSession=0;$activeBefore=$null;$activeAfter=$null;$activeReadableBefore=$false;$activeReadableAfter=$false;$activeSelfOnly=$false;$peakBefore=$null;$peakAfter=$null;$limitFlagsBefore=$null;$limitFlagsAfter=$null;$pmTerminal=$false;$workloadTerminal=$false;$pmExit=$null;$workloadExit=$null;[uint32]$pmExitRaw=259;[uint32]$workloadExitRaw=259;$pmExitIdentity=$false;$workloadExitIdentity=$false;$pmSessionAbsent=$false;$outputExceeded=$false;$timedOut=$false;$drainFault=$null;$proof=$null;$failure=$null;$status='failed';$started=[DateTimeOffset]::UtcNow
try{
  $parentProcess=[Diagnostics.Process]::GetCurrentProcess();$parentHandle=$parentProcess.Handle;if($parentHandle -eq [IntPtr]::Zero){throw "collector original parent handle is null"};$parentHandleAcquired=$true;$parentPath=$parentProcess.MainModule.FileName;$parentStartUtc=$parentProcess.StartTime.ToUniversalTime().ToString('o')
  $sessionMatch=[Sr0DisplaySessionV4]::MatchesActive([ref]$currentSession,[ref]$activeConsoleSession);if(-not $sessionMatch){throw "interactive session mismatch current=$currentSession active=$activeConsoleSession"}
  $job=[Sr0OwnedJobProcess]::CreateCurrentProcess(1073741824);$initial=$job.QueryPeakJobMemory();$activeBefore=$initial.ActiveProcessCount;$activeReadableBefore=$true;$peakBefore=$initial.PeakJobMemoryUsedBytes;$limitFlagsBefore=$initial.LimitFlags
  if($initial.JobMemoryLimitBytes -ne 1073741824 -or $initial.LimitFlags -ne [Sr0OwnedJobProcess]::JobMemoryOnlyFlags -or $activeBefore -ne 1){throw 'collector job admission proof failed'}
  $desktop=[Sr0DisplayDesktopV4]::Probe();$desktopName=$desktop.Name;$desktopNameRead=$desktop.NameRead;$desktopLastError=$desktop.LastError;$desktopAvailable=$desktop.Available -and $desktopNameRead -and $desktopName -ceq 'Default'
  $start=[ordered]@{kind='sr0-display-collector-v4-start';status=if($desktopAvailable){'admitted'}else{'failed'};taskName=$TaskName;parentPid=$parentProcess.Id;parentPath=$parentPath;parentStartTimeUtc=$parentStartUtc;parentHandle=$parentHandle.ToInt64();parentHandleRetained=($parentHandle -ne [IntPtr]::Zero);parentHandleAcquired=$parentHandleAcquired;sessionMatch=$sessionMatch;currentSession=$currentSession;activeConsoleSession=$activeConsoleSession;jobMemoryLimitBytes=$initial.JobMemoryLimitBytes;limitFlags=$initial.LimitFlags;activeProcessCount=$activeBefore;peakJobMemoryUsedBytes=$peakBefore;presentMonExe=$pmFull;presentMonSha256=$pmObserved;presentMonSession=$pmSession;presentMonCsv=$pmCsv;maxCsvBytes=$MaxCsvBytes;maxStdoutBytes=$MaxStdoutBytes;maxStderrBytes=$MaxStderrBytes;deadlineSeconds=$DeadlineSeconds;pollSeconds=$PollSeconds;noActivate=[bool]$NoActivate;desktopAvailable=$desktopAvailable;desktopNameRead=$desktopNameRead;desktopLastError=$desktopLastError;desktopName=$desktopName;startedAt=$started.ToString('o')};Write-AtomicFresh $startFull (($start|ConvertTo-Json -Depth 12)+"`r`n");if(-not $desktopAvailable){throw "interactive input desktop unavailable name=$desktopName lastError=$desktopLastError"}
  $deadline=[DateTime]::UtcNow.AddSeconds(60);while(-not $lockHeld -and [DateTime]::UtcNow -lt $deadline){$lockHeld=Acquire-Lock $lockOwner;if(-not $lockHeld){Start-Sleep -Seconds 1}};if(-not $lockHeld){throw 'desktop lock did not become free'}
  if(Test-Path -LiteralPath $pmCsv){throw 'PresentMon CSV must be fresh'}
  $timed=$Runs*($Warmup+$Measure+25)+60;$pmArgs=@('--v1_metrics','--qpc_time','--no_track_gpu','--no_track_input','--no_console_stats','--write_display_metadata','--session_name',$pmSession,'--output_file',$pmCsv,'--timed',"$timed",'--terminate_after_timed');$pm=Start-Owned $pmFull $pmArgs $runFull;$pmHandleAcquired=$true;$pmOutState=New-Object Sr0DisplayDrainStateV4;$pmErrState=New-Object Sr0DisplayDrainStateV4;$pmOutTask=[Sr0DisplayDrainV4]::Start($pm.StandardOutput,$MaxStdoutBytes,$pmStdoutPath,$pmOutState);$pmErrTask=[Sr0DisplayDrainV4]::Start($pm.StandardError,$MaxStderrBytes,$pmStderrPath,$pmErrState);$pmStartDeadline=[DateTime]::UtcNow.AddSeconds(60);while(-not $pmStarted -and [DateTime]::UtcNow -lt $pmStartDeadline){Start-Sleep -Milliseconds 500;if([Sr0DisplayDrainV4]::IsExceeded($pmOutState) -or [Sr0DisplayDrainV4]::IsExceeded($pmErrState)){$outputExceeded=$true;throw 'PresentMon stream output cap exceeded before recording'};if($pm.HasExited){throw 'PresentMon exited before recording'};if((Test-Path -LiteralPath $pmCsv -PathType Leaf) -and ((Get-Item -LiteralPath $pmCsv).Length -gt 0)){$pmStarted=$true;$pmStartObservedAt=[DateTimeOffset]::UtcNow.ToString('o')}};if(-not $pmStarted){throw 'PresentMon recording did not become observable within 60 seconds'};Start-Sleep -Seconds 5
  $taskArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',$frozenFull,'-Base',$baseFull,'-ControlRoot',$controlFull,'-RunRoot',$runFull,'-ResultFile',$resultFull,'-Runs',"$Runs",'-Warmup',"$Warmup",'-Measure',"$Measure",'-Instr','full','-Rows',"$Rows",'-KeyRate',"$KeyRate",'-LifecycleProof','-NoActivate');if($NoResources){$taskArgs+= '-NoResources'};$workload=Start-Owned $powershell $taskArgs $baseFull;$workloadHandleAcquired=$true;$workOutState=New-Object Sr0DisplayDrainStateV4;$workErrState=New-Object Sr0DisplayDrainStateV4;$workOutTask=[Sr0DisplayDrainV4]::Start($workload.StandardOutput,$MaxStdoutBytes,$workStdoutPath,$workOutState);$workErrTask=[Sr0DisplayDrainV4]::Start($workload.StandardError,$MaxStderrBytes,$workStderrPath,$workErrState)
  $runDeadline=[DateTime]::UtcNow.AddSeconds($DeadlineSeconds);while(-not $workload.HasExited -and [DateTime]::UtcNow -lt $runDeadline){Start-Sleep -Seconds $PollSeconds;if((Test-Path -LiteralPath $pmCsv -PathType Leaf) -and ((Get-Item -LiteralPath $pmCsv).Length -gt $MaxCsvBytes)){$outputExceeded=$true;break};if([Sr0DisplayDrainV4]::IsExceeded($pmOutState) -or [Sr0DisplayDrainV4]::IsExceeded($pmErrState) -or [Sr0DisplayDrainV4]::IsExceeded($workOutState) -or [Sr0DisplayDrainV4]::IsExceeded($workErrState)){$outputExceeded=$true;break}}
  if(-not $workload.HasExited){$timedOut=(-not $outputExceeded);try{$workload.Kill()}catch{}};try{[void]$workload.WaitForExit(15000)}catch{}
  $logman=Join-Path $env:SystemRoot 'System32\logman.exe';if($pm -and -not $pm.HasExited -and (Test-Path -LiteralPath $logman -PathType Leaf)){try{$pmStop=Start-Owned $logman @('stop',$pmSession,'-ets') $runFull;$pmStopHandleAcquired=$true;$pmStopOutState=New-Object Sr0DisplayDrainStateV4;$pmStopErrState=New-Object Sr0DisplayDrainStateV4;$pmStopOutTask=[Sr0DisplayDrainV4]::Start($pmStop.StandardOutput,$MaxStdoutBytes,$pmStopStdoutPath,$pmStopOutState);$pmStopErrTask=[Sr0DisplayDrainV4]::Start($pmStop.StandardError,$MaxStderrBytes,$pmStopStderrPath,$pmStopErrState);[void]$pmStop.WaitForExit(30000);$pmStopExit=[int64]$pmStop.ExitCode}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}};if($timedOut -or $outputExceeded -or ($pm -and -not $pm.HasExited)){try{$pm.Kill()}catch{}};try{[void]$pm.WaitForExit(60000)}catch{}
  if($pm){$pm.Refresh();$pmExit=[int64]$pm.ExitCode;$pmTerminal=[Sr0DisplayProcessV4]::Terminal($pm.Handle,[ref]$pmExitRaw);$pmExitIdentity=$pmTerminal -and ([Sr0DisplayProcessV4]::SignedDword($pmExitRaw) -eq $pmExit)}
  if($workload){$workload.Refresh();$workloadExit=[int64]$workload.ExitCode;$workloadTerminal=[Sr0DisplayProcessV4]::Terminal($workload.Handle,[ref]$workloadExitRaw);$workloadExitIdentity=$workloadTerminal -and ([Sr0DisplayProcessV4]::SignedDword($workloadExitRaw) -eq $workloadExit)}
  if($pmTerminal -and (Test-Path -LiteralPath $logman -PathType Leaf)){try{$pmQuery=Start-Owned $logman @('query',$pmSession,'-ets') $runFull;$pmQueryHandleAcquired=$true;$pmQueryOutState=New-Object Sr0DisplayDrainStateV4;$pmQueryErrState=New-Object Sr0DisplayDrainStateV4;$pmQueryOutTask=[Sr0DisplayDrainV4]::Start($pmQuery.StandardOutput,$MaxStdoutBytes,$pmQueryStdoutPath,$pmQueryOutState);$pmQueryErrTask=[Sr0DisplayDrainV4]::Start($pmQuery.StandardError,$MaxStderrBytes,$pmQueryStderrPath,$pmQueryErrState);[void]$pmQuery.WaitForExit(30000);$pmQueryExit=[int64]$pmQuery.ExitCode}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}
  if($pmOutTask -and -not $pmOutTask.Wait(15000)){throw 'PresentMon stdout drain timeout'};if($pmErrTask -and -not $pmErrTask.Wait(15000)){throw 'PresentMon stderr drain timeout'};if($pmStopOutTask -and -not $pmStopOutTask.Wait(15000)){throw 'PresentMon stop stdout drain timeout'};if($pmStopErrTask -and -not $pmStopErrTask.Wait(15000)){throw 'PresentMon stop stderr drain timeout'};if($workOutTask -and -not $workOutTask.Wait(15000)){throw 'workload stdout drain timeout'};if($workErrTask -and -not $workErrTask.Wait(15000)){throw 'workload stderr drain timeout'}
  if($pmQueryOutTask -and -not $pmQueryOutTask.Wait(15000)){throw 'PresentMon query stdout drain timeout'};if($pmQueryErrTask -and -not $pmQueryErrTask.Wait(15000)){throw 'PresentMon query stderr drain timeout'}
  if($pmQueryExit -ne $null){$queryText=(Read-BoundedText $pmQueryStdoutPath)+(Read-BoundedText $pmQueryStderrPath);$pmSessionAbsent=($pmQueryExit -ne 0 -and $queryText -match '(?i)(not found|does not exist|cannot find|data collector set.*(not|does not))')}
  $drainFault=if([Sr0DisplayDrainV4]::IsExceeded($pmOutState) -or [Sr0DisplayDrainV4]::IsExceeded($pmErrState) -or [Sr0DisplayDrainV4]::IsExceeded($workOutState) -or [Sr0DisplayDrainV4]::IsExceeded($workErrState) -or ($pmStopOutState -and [Sr0DisplayDrainV4]::IsExceeded($pmStopOutState)) -or ($pmStopErrState -and [Sr0DisplayDrainV4]::IsExceeded($pmStopErrState)) -or ($pmQueryOutState -and [Sr0DisplayDrainV4]::IsExceeded($pmQueryOutState)) -or ($pmQueryErrState -and [Sr0DisplayDrainV4]::IsExceeded($pmQueryErrState))){'stream output cap exceeded'}else{$null};if($drainFault){$outputExceeded=$true;throw $drainFault}
  $proof=Parse-WorkloadReceipt -Path $resultFull -Runs $Runs -NoResources:$NoResources
  $final=$job.WaitForOnlyCurrent(30000);[Sr0OwnedJobProcess]::RequireOnlyCurrent($final);$activeAfter=$final.ActiveProcessCount;$activeReadableAfter=$true;$activeSelfOnly=($activeAfter -eq 1);$peakAfter=$final.PeakJobMemoryUsedBytes;$limitFlagsAfter=$final.LimitFlags
  $releaseAllowed=[bool]($pmTerminal -and $pmExitIdentity -and $pmSessionAbsent -and $workloadTerminal -and $workloadExitIdentity -and $proof.ownershipTerminal -and $activeSelfOnly -and -not $timedOut -and -not $outputExceeded)
  if(-not $releaseAllowed){throw 'collector terminal, workload proof, or active-self proof missing'}
  Release-Lock $lockOwner;$lockReleased=$true;$status=if($proof.qualificationPass -and $pmExit -eq 0 -and $workloadExit -eq 0){'completed'}else{'qualification-failed'}
}catch{$failure=$_.Exception.Message}
finally{
  if($null -ne $pm -and -not $pm.HasExited){try{$pm.Kill()}catch{};try{[void]$pm.WaitForExit(15000)}catch{}}
  if($null -ne $workload -and -not $workload.HasExited){try{$workload.Kill()}catch{};try{[void]$workload.WaitForExit(15000)}catch{}}
  if($null -ne $pmStop -and -not $pmStop.HasExited){try{$pmStop.Kill()}catch{};try{[void]$pmStop.WaitForExit(15000)}catch{}}
  if($null -ne $pmQuery -and -not $pmQuery.HasExited){try{$pmQuery.Kill()}catch{};try{[void]$pmQuery.WaitForExit(15000)}catch{}}
  if($pm -and -not $pmSessionAbsent){$cleanupLogman=Join-Path $env:SystemRoot 'System32\logman.exe';if(Test-Path -LiteralPath $cleanupLogman -PathType Leaf){try{if(-not $pmStop){$pmStop=Start-Owned $cleanupLogman @('stop',$pmSession,'-ets') $runFull;$pmStopHandleAcquired=$true;$pmStopOutState=New-Object Sr0DisplayDrainStateV4;$pmStopErrState=New-Object Sr0DisplayDrainStateV4;$pmStopOutTask=[Sr0DisplayDrainV4]::Start($pmStop.StandardOutput,$MaxStdoutBytes,$pmStopStdoutPath,$pmStopOutState);$pmStopErrTask=[Sr0DisplayDrainV4]::Start($pmStop.StandardError,$MaxStderrBytes,$pmStopStderrPath,$pmStopErrState);[void]$pmStop.WaitForExit(30000);$pmStopExit=[int64]$pmStop.ExitCode};if(-not $pmQuery){$pmQuery=Start-Owned $cleanupLogman @('query',$pmSession,'-ets') $runFull;$pmQueryHandleAcquired=$true;$pmQueryOutState=New-Object Sr0DisplayDrainStateV4;$pmQueryErrState=New-Object Sr0DisplayDrainStateV4;$pmQueryOutTask=[Sr0DisplayDrainV4]::Start($pmQuery.StandardOutput,$MaxStdoutBytes,$pmQueryStdoutPath,$pmQueryOutState);$pmQueryErrTask=[Sr0DisplayDrainV4]::Start($pmQuery.StandardError,$MaxStderrBytes,$pmQueryStderrPath,$pmQueryErrState);[void]$pmQuery.WaitForExit(30000);$pmQueryExit=[int64]$pmQuery.ExitCode};if($pmQueryExit -ne $null){$queryText=(Read-BoundedText $pmQueryStdoutPath)+(Read-BoundedText $pmQueryStderrPath);$pmSessionAbsent=($pmQueryExit -ne 0 -and $queryText -match '(?i)(not found|does not exist|cannot find|data collector set.*(not|does not))')}}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}}
  foreach($drainTask in @($pmOutTask,$pmErrTask,$workOutTask,$workErrTask,$pmStopOutTask,$pmStopErrTask,$pmQueryOutTask,$pmQueryErrTask)){if($drainTask -and -not $drainTask.Wait(15000)){$failure=if($failure){$failure}else{'stream drain did not terminate'}}}
  if($null -ne $job -and $null -eq $activeAfter){try{$final=$job.QueryPeakJobMemory();$activeAfter=$final.ActiveProcessCount;$activeReadableAfter=$true;$activeSelfOnly=($activeAfter -eq 1);$peakAfter=$final.PeakJobMemoryUsedBytes;$limitFlagsAfter=$final.LimitFlags}catch{}}
  if($lockHeld -and $releaseAllowed -and -not $lockReleased){try{Release-Lock $lockOwner;$lockReleased=$true}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}
  if($lockReleased){try{Disable-ScheduledTask -TaskName $TaskName -ErrorAction Stop|Out-Null}catch{$failure=if($failure){$failure}else{$_.Exception.Message}}}
  $status=if($lockReleased -and $releaseAllowed -and $null -eq $failure){if($proof -and $proof.qualificationPass -and $pmExit -eq 0 -and $workloadExit -eq 0){'completed'}else{'qualification-failed'}}else{'failed'}
  $receipt=[ordered]@{kind='sr0-display-collector-v4';status=$status;taskName=$TaskName;tag=$Tag;parentPid=if($parentProcess){$parentProcess.Id}else{$null};parentPath=$parentPath;parentStartTimeUtc=$parentStartUtc;parentOriginalHandle=$parentHandle.ToInt64();parentOriginalHandleRetained=($parentHandle -ne [IntPtr]::Zero);parentOriginalHandleAcquired=$parentHandleAcquired;sessionMatch=$sessionMatch;desktopAvailable=$desktopAvailable;desktopNameRead=$desktopNameRead;desktopLastError=$desktopLastError;desktopName=$desktopName;currentSession=$currentSession;activeConsoleSession=$activeConsoleSession;startReceipt=$startFull;helperSha256=$helperObserved;frozenTaskSha256=$frozenObserved;parserSha256=$parserObserved;presentMonSha256=$pmObserved;jobMemoryLimitBytes=1073741824;limitFlagsBefore=$limitFlagsBefore;limitFlagsAfter=$limitFlagsAfter;peakJobMemoryBeforeBytes=$peakBefore;peakJobMemoryAfterBytes=$peakAfter;activeReadableBefore=$activeReadableBefore;activeBefore=$activeBefore;activeReadableAfter=$activeReadableAfter;activeAfter=$activeAfter;activeSelfOnly=$activeSelfOnly;presentMonSession=$pmSession;presentMonStarted=$pmStarted;presentMonStartObservedAt=$pmStartObservedAt;presentMonSessionAbsent=$pmSessionAbsent;presentMonCsv=$pmCsv;presentMonHandle=if($pm){$pm.Handle.ToInt64()}else{$null};presentMonHandleAcquired=$pmHandleAcquired;presentMonTerminal=$pmTerminal;presentMonExit=$pmExit;presentMonExitRaw=$pmExitRaw;presentMonExitIdentity=$pmExitIdentity;presentMonStopHandle=if($pmStop){$pmStop.Handle.ToInt64()}else{$null};presentMonStopHandleAcquired=$pmStopHandleAcquired;presentMonStopExit=$pmStopExit;presentMonQueryHandle=if($pmQuery){$pmQuery.Handle.ToInt64()}else{$null};presentMonQueryHandleAcquired=$pmQueryHandleAcquired;presentMonQueryExit=$pmQueryExit;workloadHandle=if($workload){$workload.Handle.ToInt64()}else{$null};workloadHandleAcquired=$workloadHandleAcquired;workloadTerminal=$workloadTerminal;workloadExit=$workloadExit;workloadExitRaw=$workloadExitRaw;workloadExitIdentity=$workloadExitIdentity;presentMonStdoutBytes=Drain-Bytes $pmOutTask;presentMonStderrBytes=Drain-Bytes $pmErrTask;presentMonStopStdoutBytes=Drain-Bytes $pmStopOutTask;presentMonStopStderrBytes=Drain-Bytes $pmStopErrTask;presentMonQueryStdoutBytes=Drain-Bytes $pmQueryOutTask;presentMonQueryStderrBytes=Drain-Bytes $pmQueryErrTask;workloadStdoutBytes=Drain-Bytes $workOutTask;workloadStderrBytes=Drain-Bytes $workErrTask;outputExceeded=$outputExceeded;timedOut=$timedOut;streamFault=$drainFault;workloadProof=$proof;lockHeld=$lockHeld;releaseAllowed=$releaseAllowed;lockReleased=$lockReleased;failure=$failure;startedAt=$started.ToString('o');endedAt=[DateTimeOffset]::UtcNow.ToString('o')}
  $memoryParent=Split-Path -Parent $memoryFull;if(-not(Test-Path -LiteralPath $memoryParent)){[IO.Directory]::CreateDirectory($memoryParent)|Out-Null};Write-AtomicFresh $memoryFull (($receipt|ConvertTo-Json -Depth 18)+"`r`n")
  if($job){$job.Dispose()}
}
if($status -eq 'completed'){exit 0}else{exit 1}
