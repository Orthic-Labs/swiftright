[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RootPath,
  [Parameter(Mandatory)][string]$OutputPath
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Read-Bounded([string]$Path,[string]$Label){$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;Require (-not $item.PSIsContainer) "$Label is a directory";Require (($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) "$Label is reparse";Require ($item.Length -le 2097152) "$Label exceeds 2 MiB";return [IO.File]::ReadAllText($item.FullName)}
function Has([string]$Text,[string]$Needle,[string]$Label){Require ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -ge 0) "$Label missing: $Needle"}
function Lacks([string]$Text,[string]$Needle,[string]$Label){Require ($Text.IndexOf($Needle,[StringComparison]::Ordinal) -lt 0) "$Label forbidden: $Needle"}
function Validate-Helper([string]$Text){
  Has $Text 'public sealed class Sr0RootTransportJobV1' 'helper class'
  Has $Text 'public const uint JobMemoryOnlyFlags = 0x200;' 'memory-only flags'
  Has $Text 'public const ulong BudgetBytes = 268435456UL;' '256 MiB budget'
  Has $Text 'EntryPoint="CreateJobObjectW"' 'CreateJobObject binding'
  Has $Text 'EntryPoint="SetInformationJobObject"' 'SetInformationJobObject binding'
  Has $Text 'EntryPoint="AssignProcessToJobObject"' 'AssignProcessToJobObject binding'
  Has $Text 'EntryPoint="QueryInformationJobObject"' 'QueryInformationJobObject binding'
  Has $Text 'EntryPoint="IsProcessInJob"' 'membership binding'
  Has $Text 'EntryPoint="TerminateProcess"' 'termination binding'
  Has $Text 'EntryPoint="WaitForSingleObject"' 'wait binding'
  Has $Text 'EntryPoint="GetExitCodeProcess"' 'exit binding'
  Has $Text 'EntryPoint="CloseHandle"' 'close binding'
  Has $Text 'info.JobMemoryLimit=new UIntPtr(BudgetBytes)' 'memory admission'
  Has $Text 'if (proof.ActiveCount != 1)' 'initial self-only proof'
  Has $Text 'if (ext.BasicLimitInformation.LimitFlags != JobMemoryOnlyFlags || limit != BudgetBytes || peak > limit)' 'active cap proof'
  Has $Text 'while (size <= 1048576)' 'bounded process query'
  Has $Text 'new HashSet<uint>()' 'complete process identity'
  Has $Text 'if(pid==self)continue' 'self exclusion'
  Has $Text 'if(!IsProcessInJob(child,job,out member)||!member)continue' 'foreign process rejection'
  Has $Text 'public static bool Terminal' 'terminal proof'
  Lacks $Text '0x2000' 'kill-on-close flag'
  Lacks $Text 'KillOnJobClose' 'kill-on-close option'
  Lacks $Text 'TerminateJobObject' 'whole-job kill fallback'
}
function Validate-Wrapper([string]$Text){
  Has $Text '$actualHelperSha=Hash-BoundedFile $helperItem.FullName' 'helper hash admission'
  Has $Text 'Require ($actualHelperSha -ceq $HelperSha256.ToLowerInvariant())' 'helper hash comparison'
  Has $Text 'Add-Type -Path $helperItem.FullName' 'helper load'
  Has $Text '$job=[Sr0RootTransportJobV1]::CreateCurrentProcess()' 'job admission'
  Has $Text '$scriptItem=Require-BoundedFile $ScriptPath' 'post-admission script bound'
  Has $Text 'Require ($actualScriptSha -ceq $ScriptSha256.ToLowerInvariant())' 'script hash admission'
  Has $Text '$childHandle=$child.Handle' 'immediate child handle'
  Has $Text '$watch=[Diagnostics.Stopwatch]::StartNew()' 'monotonic deadline clock'
  Has $Text 'while(-not $child.HasExited -and $watch.Elapsed.TotalSeconds -lt $DeadlineSeconds)' 'bounded deadline'
  Has $Text '$cleanup=$job.TerminateOwnedChildren(1,15000)' 'owned cleanup'
  Has $Text '[Sr0RootTransportJobV1]::Terminal($childHandle' 'kernel terminal proof'
  Has $Text '$childExitIdentity=$childTerminal -and $childExitSigned -eq $childExit' 'exit identity proof'
  Has $Text '$final=$job.WaitForOnlyCurrent(15000)' 'final active proof'
  Has $Text 'scriptSizeBytes=' 'script size receipt'
  Has $Text 'helperSha256=' 'helper pin receipt'
  Has $Text 'helperSizeBytes=' 'helper size receipt'
  Has $Text 'peakAfterBytes=' 'peak receipt'
  Has $Text 'activeAfter=' 'active receipt'
  Has $Text 'cleanupTerminated=' 'cleanup count receipt'
  Has $Text 'function Write-AtomicFresh' 'atomic receipt publication'
  Has $Text 'function Short-Error' 'bounded scalar error'
  Has $Text '2097152' '2 MiB source bound'
  Lacks $Text 'Stop-Process' 'global process termination'
  Lacks $Text 'taskkill' 'global process termination'
  Lacks $Text '[IO.File]::Delete' 'destructive cleanup'
}
function Expect-Reject([string]$Label,[scriptblock]$Check){$rejected=$false;try{&$Check}catch{$rejected=$true};Require $rejected "$Label mutation was accepted";return $Label}
function Write-AtomicFresh([string]$Path,[object]$Value){Require (-not(Test-Path -LiteralPath $Path)) "controls output must be fresh: $Path";$parent=Split-Path -Parent ([IO.Path]::GetFullPath($Path));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$tmp="$Path.$PID.$([guid]::NewGuid().ToString('N')).tmp";$bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 8)+"`r`n");$stream=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()};[IO.File]::Move($tmp,$Path)}
$root=[IO.Path]::GetFullPath($RootPath);$helperText=Read-Bounded (Join-Path $root 'Sr0RootTransportJobV1.cs') 'helper';$wrapperText=Read-Bounded (Join-Path $root 'run-root-transport-job-v1.ps1') 'wrapper';Validate-Helper $helperText;Validate-Wrapper $wrapperText
$hashIndex=$wrapperText.IndexOf('$actualHelperSha=Hash-BoundedFile $helperItem.FullName',[StringComparison]::Ordinal);$loadIndex=$wrapperText.IndexOf('Add-Type -Path $helperItem.FullName',[StringComparison]::Ordinal);Require ($hashIndex -ge 0 -and $loadIndex -gt $hashIndex) 'helper hash admission occurs before helper load';$jobIndex=$wrapperText.IndexOf('$job=[Sr0RootTransportJobV1]::CreateCurrentProcess()',[StringComparison]::Ordinal);$scriptIndex=$wrapperText.IndexOf('$scriptItem=Require-BoundedFile $ScriptPath',[StringComparison]::Ordinal);Require ($jobIndex -ge 0 -and $scriptIndex -gt $jobIndex) 'script admission occurs before root job admission'
$faults=[System.Collections.Generic.List[string]]::new();$faults.Add((Expect-Reject 'helper-budget' {Validate-Helper ($helperText.Replace('268435456UL','134217728UL'))}));$faults.Add((Expect-Reject 'helper-kill-flag' {Validate-Helper ($helperText.Replace('0x200;','0x2000;'))}));$faults.Add((Expect-Reject 'wrapper-file-cap' {Validate-Wrapper ($wrapperText.Replace('2097152','67108864'))}));$faults.Add((Expect-Reject 'wrapper-missing-owned-cleanup' {Validate-Wrapper ($wrapperText.Replace('$cleanup=$job.TerminateOwnedChildren(1,15000)','$cleanup=$job.WaitForOnlyCurrent(15000)'))}));$faults.Add((Expect-Reject 'wrapper-delayed-handle' {Validate-Wrapper ($wrapperText.Replace('$childHandle=$child.Handle','$childHandle=[IntPtr]::Zero'))}));$faults.Add((Expect-Reject 'wrapper-hash-inversion' {Validate-Wrapper ($wrapperText.Replace('-ceq $ScriptSha256.ToLowerInvariant()','-ne $ScriptSha256.ToLowerInvariant()'))}));
$receipt=[ordered]@{kind='sr0-root-transport-controls-v1';status='passed';helperBytes=([Text.Encoding]::UTF8.GetByteCount($helperText));wrapperBytes=([Text.Encoding]::UTF8.GetByteCount($wrapperText));faults=$faults;jobAdmissionBeforeScript=$true;boundedReadBytes=2097152;budgetBytes=268435456;limitFlags=512;killOnClose=$false};Write-AtomicFresh $OutputPath $receipt
