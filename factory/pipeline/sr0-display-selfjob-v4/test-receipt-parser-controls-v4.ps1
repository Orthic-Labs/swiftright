# Source controls: same parser, archived receipt, in-memory fault files.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$ParserPath,[Parameter(Mandatory)][string]$ArchivedReceipt,[Parameter(Mandatory)][string]$OutputPath,[ValidateRange(1,20)][int]$Runs=1,[switch]$NoResources)
$ErrorActionPreference='Stop'
if((Get-Item -LiteralPath $ParserPath).Length -gt 256KB){throw 'parser exceeds bound'}
if((Get-Item -LiteralPath $ArchivedReceipt).Length -gt 2MB){throw 'archived receipt exceeds bound'}
. $ParserPath
$outParent=Split-Path -Parent $OutputPath;[IO.Directory]::CreateDirectory($outParent)|Out-Null
$base=Read-BoundedReceipt $ArchivedReceipt
function Run-Case([string]$Name,[string]$Text,[bool]$ExpectOwnership,[bool]$ExpectQualification) {
  $p=Join-Path $outParent "parser-$Name.txt";[IO.File]::WriteAllText($p,$Text)
  $r=Parse-WorkloadReceipt -Path $p -Runs $Runs -NoResources:$NoResources
  if ([bool]$r.ownershipTerminal -ne $ExpectOwnership -or [bool]$r.qualificationPass -ne $ExpectQualification) { throw "fault case $Name mismatch" }
  return [ordered]@{name=$Name;ownershipTerminal=$r.ownershipTerminal;qualificationPass=$r.qualificationPass;workerRows=$r.workerRows;samplerRows=$r.samplerRows;streamDrainRows=$r.streamDrainRows}
}
$cases=@();$cases += Run-Case 'baseline' $base $true $true
$naturalNonzero=([regex]' exit=0 kernel_terminal=1 kernel_exit_raw=0 kernel_exit=0 dotnet_exit=0').Replace($base,' exit=17 kernel_terminal=1 kernel_exit_raw=17 kernel_exit=17 dotnet_exit=17',1)
$cases += Run-Case 'natural-nonzero' $naturalNonzero $true $false
$inconsistent=([regex]' exit=0 kernel_terminal=1 kernel_exit_raw=0 kernel_exit=0 dotnet_exit=0').Replace($base,' exit=0 kernel_terminal=1 kernel_exit_raw=0 kernel_exit=17 dotnet_exit=0',1)
$cases += Run-Case 'identity' $inconsistent $false $false
$streamFault=([regex]'worker_stdout=1 worker_stderr=1').Replace($base,'worker_stdout=0 worker_stderr=1',1)
$cases += Run-Case 'stream-drain' $streamFault $false $false
$terminalFault=([regex]'kernel_terminal=1').Replace($base,'kernel_terminal=0',1)
$cases += Run-Case 'terminal' $terminalFault $false $false
$cases += Run-Case 'count' ($base -replace '(?m)^stream_drains .*\r?$','') $false $false
$obj=[ordered]@{schema='sr0-display-selfjob-parser-controls-v4';status='source-admitted';archivedReceipt=$ArchivedReceipt;runs=$Runs;noResources=[bool]$NoResources;cases=$cases;nativeActions=0;lockActions=0}
$obj|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $OutputPath -Encoding UTF8
$obj|ConvertTo-Json -Depth 12
