# Bounded adapter for one captured WorkloadWin PresentMon CSV.
# It binds original PID evidence to frozen workload-analysis-v3, but never claims display qualification.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CsvPath,
  [Parameter(Mandatory)][string]$ResultPath,
  [Parameter(Mandatory)][string]$AnalyzerPath,
  [Parameter(Mandatory)][string]$RunRoot,
  [Parameter(Mandatory)][string]$AnalyzerOutRoot,
  [Parameter(Mandatory)][string]$OutputPath,
  [Parameter(Mandatory)][ValidateRange(1,2147483647)][int64]$WorkloadPid,
  [ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RunId='r1',
  [ValidateRange(1,20)][int]$ExpectedRuns=1,
  [ValidateRange(0.1,10.0)][double]$ExpectedScale=2.5,
  [ValidateRange(1024,67108864)][int64]$MaxCsvBytes=67108864,
  [ValidateRange(1,1000000)][int]$MaxRows=1000000
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Require-InputFile([string]$Path,[int64]$MaxBytes){
  Require (Test-Path -LiteralPath $Path -PathType Leaf) "input missing: $Path"
  $item=Get-Item -LiteralPath $Path -Force
  Require (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) "reparse input rejected: $Path"
  Require ($item.Length -le $MaxBytes) "input exceeds bound: $Path"
  return $item
}
function Split-CsvFieldsV1([string]$Line){
  $out=New-Object 'System.Collections.Generic.List[string]';$b=New-Object Text.StringBuilder;$quoted=$false
  for($i=0;$i -lt $Line.Length;$i++){
    $c=$Line[$i]
    if($c -eq [char]34){
      if($quoted -and $i+1 -lt $Line.Length -and $Line[$i+1] -eq [char]34){[void]$b.Append([char]34);$i++;continue}
      $quoted=-not $quoted;continue
    }
    if($c -eq ',' -and -not $quoted){[void]$out.Add($b.ToString());$b.Length=0;continue}
    [void]$b.Append($c)
  }
  Require (-not $quoted) 'CSV unterminated quoted field'
  [void]$out.Add($b.ToString());return @($out)
}
function Finite-Double([string]$Value,[ref]$Parsed){
  [double]$parsedLocal=0.0
  if(-not [double]::TryParse($Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsedLocal)){return $false}
  $Parsed.Value=$parsedLocal
  return (-not [double]::IsNaN($parsedLocal) -and -not [double]::IsInfinity($parsedLocal))
}
function Write-AtomicJson([string]$Path,[object]$Value){
  $full=[IO.Path]::GetFullPath($Path);$parent=Split-Path -Parent $full
  if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
  if(Test-Path -LiteralPath $full){throw "output must be fresh: $full"}
  $tmp="$full.$PID.$([guid]::NewGuid().ToString('N')).tmp"
  $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 12)+"`r`n")
  $s=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$s.Write($bytes,0,$bytes.Length);$s.Flush($true)}finally{$s.Dispose()}
  [IO.File]::Move($tmp,$full)
}
function Read-ResultBinding([string]$Path,[string]$ExpectedRun,[int64]$ExpectedPid){
  $item=Require-InputFile $Path 2097152;$pidLine=$false;$exitLine=$false;$exitValue=$null
  $fs=[IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{$r=New-Object IO.StreamReader($fs,[Text.Encoding]::UTF8,$true,4096,$true);try{
    while($null -ne ($line=$r.ReadLine())){
      if($line.Length -gt 1048576){throw 'result line exceeds bound'}
      if($line -match "^pid run=$([regex]::Escape($ExpectedRun)) pid=([0-9]+) "){Require ([int64]$Matches[1] -eq $ExpectedPid) 'result pid binding mismatch';$pidLine=$true}
      if($line -match "^pid_exit run=$([regex]::Escape($ExpectedRun)) pid=([0-9]+) .* exit=(-?[0-9]+) "){Require ([int64]$Matches[1] -eq $ExpectedPid) 'result exit pid binding mismatch';$exitValue=[int64]$Matches[2];$exitLine=$true}
    }
  }finally{$r.Dispose()}}finally{$fs.Dispose()}
  Require $pidLine 'result workload PID line missing';Require $exitLine 'result workload exit line missing';Require ($exitValue -eq 0) "workload exit was $exitValue"
  return [ordered]@{run=$ExpectedRun;pid=$ExpectedPid;exit=$exitValue}
}
Require ($ExpectedScale -eq 2.5) 'Windows strict parser requires expected scale 2.5'
$csv=Require-InputFile $CsvPath $MaxCsvBytes
$analyzer=Require-InputFile $AnalyzerPath 2097152
$resultItem=Require-InputFile $ResultPath 2097152
Require (Test-Path -LiteralPath $RunRoot -PathType Container) "run root missing: $RunRoot"
$binding=Read-ResultBinding $ResultPath $RunId $WorkloadPid
$expected=@('Application','ProcessID','SwapChainAddress','Runtime','SyncInterval','PresentFlags','Dropped','TimeInSeconds','msInPresentAPI','msBetweenPresents','AllowsTearing','PresentMode','msUntilRenderComplete','msUntilDisplayed','msBetweenDisplayChange','msFlipDelay','QPCTime')
$rows=0;$workloadRows=0;$workloadQpcRows=0;$displayCandidates=0;$csvHeader=$null
$fs=[IO.File]::Open($csv.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{$reader=New-Object IO.StreamReader($fs,[Text.Encoding]::UTF8,$true,4096,$true);try{
  $header=$reader.ReadLine();Require ($null -ne $header) 'PresentMon header missing';$csvHeader=Split-CsvFieldsV1 ($header.TrimStart([char]0xFEFF));Require ($csvHeader.Count -eq $expected.Count) 'PresentMon header column count mismatch'
  for($i=0;$i -lt $expected.Count;$i++){Require ([string]$csvHeader[$i] -ceq $expected[$i]) "PresentMon header mismatch at column $i"}
  while($null -ne ($line=$reader.ReadLine())){
    Require ($line.Length -le 1048576) 'PresentMon row exceeds bound';if($line.Length -eq 0){continue};$v=Split-CsvFieldsV1 $line;Require ($v.Count -eq $expected.Count) 'PresentMon row column count mismatch';$rows++
    [int64]$rowPid=0;Require ([int64]::TryParse([string]$v[1],[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$rowPid)) 'PresentMon ProcessID invalid';[uint64]$qpc=0;Require ([uint64]::TryParse([string]$v[16],[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$qpc) -and $qpc -gt 0) 'PresentMon QPCTime invalid';[double]$seconds=0;Require (Finite-Double ([string]$v[7]) ([ref]$seconds) -and $seconds -ge 0) 'PresentMon TimeInSeconds invalid'
    if([string]$v[0] -eq 'WorkloadWin.exe' -and $rowPid -eq $WorkloadPid){$workloadRows++;$workloadQpcRows++;Require ([string]$v[6] -in @('0','1')) 'PresentMon Dropped invalid for WorkloadWin row';if([string]$v[6] -eq '0' -and -not [string]::IsNullOrWhiteSpace([string]$v[13])){[double]$until=0;Require (Finite-Double ([string]$v[13]) ([ref]$until)) 'PresentMon msUntilDisplayed invalid';$displayCandidates++}}
    Require ($rows -le $MaxRows) 'PresentMon row count exceeds bound'
  }
}finally{$reader.Dispose()}}finally{$fs.Dispose()}
Require ($rows -gt 0) 'PresentMon contains no rows';Require ($workloadRows -gt 0) 'PresentMon contains no rows for original WorkloadWin PID'
$csvHash=(Get-FileHash -LiteralPath $csv.FullName -Algorithm SHA256).Hash.ToLowerInvariant();$analyzerHash=(Get-FileHash -LiteralPath $analyzer.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$quote={param([string]$v);'"'+$v.Replace('"','\"')+'"'}
$command='python '+(& $quote $analyzer.FullName)+' --os windows --root '+(& $quote ([IO.Path]::GetFullPath($RunRoot)))+' --out '+(& $quote ([IO.Path]::GetFullPath($AnalyzerOutRoot)))+' --expect-runs '+$ExpectedRuns+' --expect-scale 2.5'
$receipt=[ordered]@{kind='sr0-display-presentmon-adapter-v1';status='qualification-held';qualificationHeld=$true;holdReason='frozen-workload-analysis-v3-pending';strictParser='qualification/tuple12-takeover/workload-analysis-v3/analyze_workload.py';strictParserPath=$analyzer.FullName;strictParserSha256=$analyzerHash;strictParserCommand=$command;runRoot=[IO.Path]::GetFullPath($RunRoot);analyzerOutRoot=[IO.Path]::GetFullPath($AnalyzerOutRoot);resultPath=$resultItem.FullName;csvPath=$csv.FullName;csvSha256=$csvHash;csvBytes=[int64]$csv.Length;csvHeaderColumns=$csvHeader.Count;csvDataRows=$rows;workloadRun=$binding.run;workloadPid=$binding.pid;workloadExit=$binding.exit;workloadRows=$workloadRows;workloadQpcRows=$workloadQpcRows;displayCandidateRows=$displayCandidates;expectedRuns=$ExpectedRuns;expectedScale=$ExpectedScale;displayQualification='pending-strict-frozen-parser';parityClaim=$false;createdAt=[DateTimeOffset]::UtcNow.ToString('o')}
Write-AtomicJson $OutputPath $receipt
exit 0
