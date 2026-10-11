# Pure Foundation serializer control only. Bounded owned compiler + console child; no renderer/window/input.
param([Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SwiftcSha256)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($PSScriptRoot)
if($root -cne 'D:\Claude\swiftright\.factory-work\hosts\padding-settled'){throw 'Exact rolling root required'}
$planPath=Join-Path $root 'package\plan.json';$plan=Get-Content -Raw $planPath|ConvertFrom-Json
$planHash=(Get-FileHash $planPath).Hash.ToLowerInvariant()
$swiftc=Join-Path (Split-Path $plan.compilerPath -Parent) 'swiftc.exe'
$source=Join-Path $root 'package\Sources\FactoryProbe\MetricsPayload.swift'
$control=Join-Path $root 'serializer-control\main.swift'
$streamHelper=Join-Path $root 'stream-seal.ps1';$cleanupHelper=Join-Path $root 'cleanup-decision.ps1'
function Assert-Inputs {
 if((Get-FileHash $planPath).Hash.ToLowerInvariant() -cne 'fe088dc1318e6ebc319c95ee169c2c91aa7e630fd19d81729389ebedb8397b20' -or (Get-FileHash $source).Hash.ToLowerInvariant() -cne 'cde9a9a3a90f52eda4134069f7c6be80ad0d7315689c8e2cdc7ae21deb0f19e1' -or (Get-FileHash $control).Hash.ToLowerInvariant() -cne '7b7b79a0e90c63aa696a7347e6ab975fe6dc811bce96b12a2e3548bf3ef64454'){throw 'Serializer source/plan drift'}
 if((Get-FileHash $swiftc).Hash.ToLowerInvariant() -cne $SwiftcSha256){throw 'Measured actual swiftc bytes required'}
 if((Get-FileHash $streamHelper).Hash.ToLowerInvariant() -cne '4e68ceab6611e6b919489f1f98f147594453257584c301cc65dacb80ca69c48d' -or (Get-FileHash $cleanupHelper).Hash.ToLowerInvariant() -cne '018d89b825634a0dc238c1201d4fd97a23acbcdaf57b82333c6097e9efd92001'){throw 'Bounded stream/cleanup helper drift'}
}
Assert-Inputs
. $streamHelper
. $cleanupHelper
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class FactorySerializerHandleV1 {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool TerminateProcess(IntPtr process, uint exitCode);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);
}
'@
$outRoot=Join-Path $root 'serializer-control-actual-r1'
if(Test-Path -LiteralPath $outRoot){throw 'Fresh serializer control output required'}
New-Item -ItemType Directory -Path $outRoot|Out-Null
$env:Path='C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;'+$env:Path
function Invoke-SerializerChild([string]$Name,[string]$File,[string]$Arguments,[int]$DeadlineMilliseconds,[string]$ExpectedExeHash=''){
 $out=Join-Path $outRoot $Name;New-Item -ItemType Directory -Path $out|Out-Null
 $si=[Diagnostics.ProcessStartInfo]::new($File,$Arguments)
 $si.UseShellExecute=$false;$si.CreateNoWindow=$true;$si.WorkingDirectory=$outRoot
 $si.RedirectStandardOutput=$true;$si.RedirectStandardError=$true
 $record=[ordered]@{kind='factory-serializer-pure-child-v1';phase=$Name;planSha256=$planHash;toolPath=$File;toolSha256=(Get-FileHash $File).Hash.ToLowerInvariant();argv=$Arguments;cwd=$outRoot;startedAt=[DateTimeOffset]::UtcNow.ToString('o');pid=$null;processStartedAt=$null;exitCode=$null;timedOut=$false;ownedExited=$false;error=$null;cleanupError=$null;cleanupAction='none';descendantOwnership='not-observed';nativeActions=0}
 $receipt=Join-Path $out 'observation.json'
 function Save-Receipt {$record|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath $receipt}
$p=$null;$handle=[IntPtr]::Zero;$stdoutFile=$null;$stderrFile=$null;$streams=@()
$record.rawStreams=@();$record.rawFileHashes=@();$record.kernelWait=$null

Save-Receipt
try {
 $stdoutFile=[IO.File]::Open((Join-Path $out 'compile.stdout.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $streams+=@{name='stdout';source=$null;file=$stdoutFile;task=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false;closure=$null;closeTask=$null}
 $stderrFile=[IO.File]::Open((Join-Path $out 'compile.stderr.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
 $streams+=@{name='stderr';source=$null;file=$stderrFile;task=$null;copyCompleted=$false;destinationClosed=$false;sealed=$false;closure=$null;closeTask=$null}
 Assert-Inputs
 if($ExpectedExeHash -and (Get-FileHash $File).Hash.ToLowerInvariant() -cne $ExpectedExeHash){throw 'Produced serializer executable drift'}
 $p=[Diagnostics.Process]::Start($si)
 $handle=$p.Handle # Force retained kernel handle before any wait or identity bookkeeping.
 $record.pid=$p.Id;$record.processStartedAt=$p.StartTime.ToUniversalTime().ToString('o');Save-Receipt
 foreach($stream in $streams){
  $source=if($stream.name -ceq 'stdout'){$p.StandardOutput.BaseStream}else{$p.StandardError.BaseStream}
  $stream.source=$source;$stream.task=$source.CopyToAsync($stream.file)
 }
 if(-not $p.WaitForExit($DeadlineMilliseconds)){$record.timedOut=$true;$record.error='Compiler deadline exceeded'}
} catch {$record.error=[string]$_}
finally {
 # No Get-Process/PID lookup or taskkill. Wait status & termination operate on same retained handle.
 try {
  if($handle -ne [IntPtr]::Zero){
   $wait=[FactorySerializerHandleV1]::WaitForSingleObject($handle,0)
   $action=Get-CompilerCleanupAction $wait ($record.timedOut -or $null -ne $record.error)
   $record.cleanupAction=$action;Save-Receipt
   if($action -eq 'terminate-owned-handle'){
    $record.descendantOwnership='unresolved-root-only-termination';Save-Receipt
    if(-not [FactorySerializerHandleV1]::TerminateProcess($handle,124)){throw ('Terminate owned handle failed: '+[Runtime.InteropServices.Marshal]::GetLastWin32Error())}
    $null=[FactorySerializerHandleV1]::WaitForSingleObject($handle,5000)
   }
   $record.kernelWait=[FactorySerializerHandleV1]::WaitForSingleObject($handle,0)
   $record.ownedExited=($record.kernelWait -eq 0)
   if($record.ownedExited){$record.exitCode=$p.ExitCode}
  }
 } catch {$record.cleanupError=[string]$_}
 Save-Receipt
 # No synchronous pipe Close/Flush/Dispose. Copy EOF & background destination closure each bounded5s.
 try {Complete-FactoryRawStreams $streams} catch {
  if($null -eq $record.cleanupError){$record.cleanupError=[string]$_}
 }
 foreach($stream in $streams){
  if(-not $stream.destinationClosed){
   Save-Receipt
   try{Close-FactoryRawStreamDestination $stream}catch{if($null -eq $record.cleanupError){$record.cleanupError=[string]$_}}
  }
 }
 $record.rawStreams=@($streams|ForEach-Object{Get-FactoryRawStreamState $_})
 $record.streamDrainComplete=($streams.Count -eq 2 -and @($record.rawStreams|Where-Object{-not $_.sealed -or -not $_.destinationClosed -or $_.taskStatus -cne 'RanToCompletion' -or $_.closureTaskStatus -cne 'RanToCompletion'}).Count -eq 0)
 foreach($stream in $streams){
  $state=Get-FactoryRawStreamState $stream
  $path=Join-Path $out ('compile.'+$stream.name+'.bin')
  $rawHash=Get-FactoryRawHash $path $state
  if($rawHash.qualification -ceq 'sealed-raw' -and (-not $record.ownedExited -or $record.kernelWait -ne 0 -or -not $record.streamDrainComplete)){$rawHash.qualification='diagnostic-partial';$rawHash.reason='compiler-kernel-or-two-stream-terminal-proof-missing'}
  $record.rawFileHashes+=@{path=('compile.'+$stream.name+'.bin');hash=$rawHash;state=$state}
 }
 $record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o');Save-Receipt
}
 if(-not $record.ownedExited -or $record.kernelWait -ne 0 -or $record.exitCode -ne 0 -or $record.error -or $record.cleanupError -or $record.timedOut -or -not $record.streamDrainComplete){throw ('Serializer '+$Name+' child unsuccessful; exact receipt retained')}
 Assert-Inputs
 return $record
}
$exe=Join-Path $outRoot 'serializer-control.exe'
$argsText='"'+$source+'" "'+$control+'" -o "'+$exe+'"'
$compile=Invoke-SerializerChild 'compile' $swiftc $argsText 30000
if(-not (Test-Path -LiteralPath $exe)){throw 'Serializer compiler produced no executable'}
$exeHash=(Get-FileHash $exe).Hash.ToLowerInvariant()
$run=Invoke-SerializerChild 'run' $exe '' 10000 $exeHash
$stdout=Join-Path $outRoot 'run\compile.stdout.bin'
$text=[IO.File]::ReadAllText($stdout)
if(@($text -split '\r?\n'|Where-Object{$_ -ceq 'SERIALIZER_CONTROL_PASS records=5 failClosed=true nativeLaunches=0'}).Count -ne 1 -or $text.Contains('SERIALIZER_CONTROL_FAIL')){throw 'Actual pure serializer control PASS missing or ambiguous'}
[ordered]@{kind='factory-serializer-control-actual-v1';passed=$true;nativeActions=0;planSha256=$planHash;sourceSha256=(Get-FileHash $source).Hash.ToLowerInvariant();controlSha256=(Get-FileHash $control).Hash.ToLowerInvariant();swiftcSha256=$SwiftcSha256;exeSha256=$exeHash;compileReceiptSha256=(Get-FileHash (Join-Path $outRoot 'compile\observation.json')).Hash.ToLowerInvariant();runReceiptSha256=(Get-FileHash (Join-Path $outRoot 'run\observation.json')).Hash.ToLowerInvariant();stdoutSha256=(Get-FileHash $stdout).Hash.ToLowerInvariant();requiredMarker='SERIALIZER_CONTROL_PASS records=5 failClosed=true nativeLaunches=0'}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $outRoot 'control.json')
