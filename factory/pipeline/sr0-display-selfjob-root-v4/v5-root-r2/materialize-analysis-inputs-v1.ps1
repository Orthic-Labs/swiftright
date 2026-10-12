# Derives frozen-analyzer inputs from sealed collector files without changing raw evidence.
# Result pid_exit handle tokens are removed only in derived result; PM stdout/stderr are joined only in derived console.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RawResultPath,
  [Parameter(Mandatory)][string]$PresentMonStdoutPath,
  [Parameter(Mandatory)][string]$PresentMonStderrPath,
  [Parameter(Mandatory)][string]$OutputRoot,
  [Parameter(Mandatory)][string]$OutputPath,
  [int64]$MaxResultBytes=2097152,
  [int64]$MaxStreamBytes=8388608
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function InputFile([string]$Path,[int64]$Cap){Require (Test-Path -LiteralPath $Path -PathType Leaf) "input missing: $Path";$i=Get-Item -LiteralPath $Path -Force;Require (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) "reparse input rejected: $Path";Require ($i.Length -le $Cap) "input exceeds bound: $Path";return $i}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Write-Fresh([string]$Path,[byte[]]$Bytes){$full=[IO.Path]::GetFullPath($Path);if(Test-Path -LiteralPath $full){throw "derived output must be fresh: $full"};$parent=Split-Path -Parent $full;if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null};$tmp="$full.$PID.$([guid]::NewGuid().ToString('N')).tmp";$s=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);try{$s.Write($Bytes,0,$Bytes.Length);$s.Flush($true)}finally{$s.Dispose()};[IO.File]::Move($tmp,$full)}
function Write-AtomicJson([string]$Path,[object]$Value){Write-Fresh $Path ([Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 12)+"`r`n"))}
$raw=InputFile $RawResultPath $MaxResultBytes;$outRaw=InputFile $PresentMonStdoutPath $MaxStreamBytes;$errRaw=InputFile $PresentMonStderrPath $MaxStreamBytes
$rawText=[IO.File]::ReadAllText($raw.FullName)
$lines=$rawText -split "`n";$derivedLines=New-Object 'System.Collections.Generic.List[string]';$handleRewrites=0;$pidExits=0
foreach($line in $lines){$clean=$line.TrimEnd("`r");if($clean -match '^pid_exit run=\S+ pid=\d+ handle=[1-9]\d+ qpc_end=\d+ exit=-?\d+'){ $updated=[regex]::Replace($clean,'^(pid_exit run=\S+ pid=\d+) handle=[1-9]\d+ (qpc_end=\d+ exit=-?\d+.*)$','$1 $2');Require ($updated -ne $clean) 'pid_exit handle normalization failed';$clean=$updated;$handleRewrites++};if($clean -match '^pid_exit run='){ $pidExits++ };[void]$derivedLines.Add($clean)}
Require ($pidExits -gt 0) 'raw result has no pid_exit records';$derivedResult=[Text.Encoding]::UTF8.GetBytes(($derivedLines -join "`r`n")+"`r`n")
$fullRoot=[IO.Path]::GetFullPath($OutputRoot);if(-not(Test-Path -LiteralPath $fullRoot -PathType Container)){[IO.Directory]::CreateDirectory($fullRoot)|Out-Null};$derivedResultPath=Join-Path $fullRoot 'result-workload.adapter.txt';$derivedConsolePath=Join-Path $fullRoot 'presentmon.console.adapter.txt';Write-Fresh $derivedResultPath $derivedResult
$consoleBytes=New-Object 'System.Collections.Generic.List[byte]';$buffer=New-Object byte[] 4096
foreach($source in @($outRaw,$errRaw)){$fs=[IO.File]::Open($source.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);try{while(($n=$fs.Read($buffer,0,$buffer.Length)) -gt 0){for($j=0;$j -lt $n;$j++){[void]$consoleBytes.Add($buffer[$j])}}}finally{$fs.Dispose()};if($source.FullName -eq $outRaw.FullName -and $consoleBytes.Count -gt 0 -and $consoleBytes[$consoleBytes.Count-1] -ne 10){[void]$consoleBytes.Add(13);[void]$consoleBytes.Add(10)}}
Write-Fresh $derivedConsolePath ([byte[]]$consoleBytes.ToArray())
$receipt=[ordered]@{kind='sr0-display-analysis-inputs-v1';status='materialized';qualificationHeld=$true;qualificationHoldReason='derived-inputs-only-frozen-analyzer-pending';rawResultPath=$raw.FullName;rawResultBytes=[int64]$raw.Length;rawResultSha256=(Hash $raw.FullName);derivedResultPath=$derivedResultPath;derivedResultBytes=[int64](Get-Item -LiteralPath $derivedResultPath).Length;derivedResultSha256=(Hash $derivedResultPath);pidExitRecords=$pidExits;pidExitHandleRewrites=$handleRewrites;rawPresentMonStdoutPath=$outRaw.FullName;rawPresentMonStdoutBytes=[int64]$outRaw.Length;rawPresentMonStdoutSha256=(Hash $outRaw.FullName);rawPresentMonStderrPath=$errRaw.FullName;rawPresentMonStderrBytes=[int64]$errRaw.Length;rawPresentMonStderrSha256=(Hash $errRaw.FullName);derivedConsolePath=$derivedConsolePath;derivedConsoleBytes=[int64](Get-Item -LiteralPath $derivedConsolePath).Length;derivedConsoleSha256=(Hash $derivedConsolePath);rawPreserved=$true;parityClaim=$false;createdAt=[DateTimeOffset]::UtcNow.ToString('o')}
Write-AtomicJson $OutputPath $receipt
exit 0
