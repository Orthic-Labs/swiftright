# Offline proof controls. Reads one explicit archived worker closure only.
param(
 [Parameter(Mandatory=$true)][string]$WorkerRoot,
 [Parameter(Mandatory=$true)][string]$ProducerRoot,
 [Parameter(Mandatory=$true)][string]$ControlRoot
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Fail([string]$m){throw ('r5f-worker-release-v2: '+$m)}
function Read-BoundedBytes([string]$Path){
 $i=Get-Item -LiteralPath $Path -Force
 if($i.PSIsContainer -or (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0)){Fail ('unsafe proof input '+$Path)}
 if($i.Length -gt 8388608){Fail ('proof input exceeds 8MiB '+$Path)}
 return ,([IO.File]::ReadAllBytes($Path))
}
function Read-Json([string]$Path){return ([Text.Encoding]::UTF8.GetString((Read-BoundedBytes $Path))).TrimStart([char]0xfeff)|ConvertFrom-Json}
function Json-Bytes($Value){return ,([Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 32 -Compress)))}
if(-not(Test-Path -LiteralPath $WorkerRoot -PathType Container)){Fail 'worker root missing'}
if(-not(Test-Path -LiteralPath $ProducerRoot -PathType Container)){Fail 'producer root missing'}
New-Item -ItemType Directory -Path $ControlRoot -ErrorAction Stop|Out-Null
. (Join-Path $PSScriptRoot 'final-exit-certificate-v2.ps1')
$root=[IO.Path]::GetFullPath($WorkerRoot);$sourceRoot=[IO.Path]::GetFullPath((Join-Path $ProducerRoot 'dependencies\uia-worker'))
$start=Read-Json (Join-Path $root 'final-start.json');$terminalPath=Join-Path $root 'terminal-worker.json';$certPath=Join-Path $root 'final-exit-certificate.json';$originalPath=Join-Path $root 'worker-exit.json';$configPath=Join-Path $root 'config.json';$contractPath=Join-Path $sourceRoot 'worker-contract.json';$workerScript=Join-Path $sourceRoot 'worker.ps1';$psExe=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$terminal=Read-Json $terminalPath;$certificate=Read-Json $certPath;$contract=Read-Json $contractPath
$expected=$start|ConvertTo-Json -Depth 32|ConvertFrom-Json
$expected|Add-Member -Force workerReceiptRef $terminalPath;$expected|Add-Member -Force workerReceiptHash ((Get-FileHash -LiteralPath $terminalPath).Hash.ToLowerInvariant())
$expected|Add-Member -Force workerExeRef $psExe;$expected|Add-Member -Force sourceContractRef $contractPath;$expected|Add-Member -Force configRef $configPath;$expected|Add-Member -Force workerScriptRef $workerScript
$sourceBindings=@($contract.sourceBindings|ForEach-Object{[pscustomobject]@{path=$_.path;ref=(Join-Path $sourceRoot $_.path);sha256=$_.sha256}});$expected|Add-Member -Force sourceBindings $sourceBindings
$localStdout=Join-Path $root 'stdout.bin';$localStderr=Join-Path $root 'stderr.bin'
$aliases=@{[string]$terminal.finalCertificateRef=$certPath;[string]$terminal.originalOutcomeRef=$originalPath}
foreach($raw in @($certificate.rawStreams)){if($raw.name -ceq 'stdout'){$aliases[[string]$raw.path]=$localStdout}elseif($raw.name -ceq 'stderr'){$aliases[[string]$raw.path]=$localStderr}}
$allowed=@($terminalPath,$certPath,$originalPath,$psExe,$contractPath,$configPath,$workerScript,$localStdout,$localStderr)+@($sourceBindings|ForEach-Object{$_.ref})+@($aliases.Keys)
$mutation=''
$reader={param($Ref)
 if($allowed -cnotcontains $Ref){Fail ('reader escaped closure '+$Ref)}
 $readPath=if($aliases.ContainsKey([string]$Ref)){$aliases[[string]$Ref]}else{$Ref};$bytes=Read-BoundedBytes $readPath
 if($mutation -eq 'config-kind-v1' -and $Ref -ceq $configPath){$x=([Text.Encoding]::UTF8.GetString($bytes)).TrimStart([char]0xfeff)|ConvertFrom-Json;$x.kind='factory-uia-snapshot-worker-config-v1';return (Json-Bytes $x)}
 if($mutation -eq 'terminal-certificate-hash' -and $Ref -ceq $terminalPath){$x=([Text.Encoding]::UTF8.GetString($bytes)).TrimStart([char]0xfeff)|ConvertFrom-Json;$x.finalCertificateHash=('0'*64);return (Json-Bytes $x)}
 return ,$bytes
}
function Invoke-Case([string]$Name){
 $script:mutation=$Name
 try{
  $e=$expected|ConvertTo-Json -Depth 32|ConvertFrom-Json
  # Positive must preserve exact parsed certificate shape; helper compares parsed sealed bytes structurally.
  $c=if($Name -eq 'positive'){$certificate}else{$certificate|ConvertTo-Json -Depth 32|ConvertFrom-Json}
  if($Name -eq 'worker-script-hash'){ $e.workerScriptHash='0'*64 }
  if($Name -eq 'retained-handle'){ $e.retainedHandle=[int64]$e.retainedHandle+1 }
  if($Name -eq 'source-binding-hash'){ $e.sourceBindings[0].sha256='0'*64 }
  if($Name -eq 'raw-stream-hash'){ $c.rawStreams[0].sha256='0'*64 }
  # Archived bytes are local, while worker identity remains original Windows path. Keep both distinct.
  $ok=Test-FactoryAllUiaWorkerReleaseProofs @([string]$expected.workerId) @([pscustomobject]@{certificate=$c;expected=$e}) $reader
  return [ordered]@{name=$Name;accepted=[bool]$ok;expectedAccepted=($Name -eq 'positive');error=''}
 }catch{return [ordered]@{name=$Name;accepted=$false;expectedAccepted=($Name -eq 'positive');error=([string]$_)}}
}
$rows=@(Invoke-Case 'positive')
foreach($case in @('config-kind-v1','worker-script-hash','retained-handle','source-binding-hash','raw-stream-hash','terminal-certificate-hash')){$rows+=Invoke-Case $case}
$positive=$rows[0].accepted -eq $true;$faults=@($rows|Select-Object -Skip 1);$passed=[bool]($positive -and @($faults|Where-Object{$_.accepted}).Count -eq 0)
$result=[ordered]@{kind='factory-mta-worker-release-controls-v2';status=if($passed){'source-control-pass'}else{'source-control-fail'};workerRoot=$root;producerRoot=$ProducerRoot;cases=$rows;nativeWindowActions=0;compilerActions=0;lockActions=0}
$json=$result|ConvertTo-Json -Depth 16;$receiptPath=Join-Path $ControlRoot 'r5f-worker-release-v2-controls.json';[IO.File]::WriteAllText($receiptPath,$json,(New-Object Text.UTF8Encoding($false)));$json
if(-not $passed){Fail 'offline release controls failed; inspect bounded receipt cases/errors'}
