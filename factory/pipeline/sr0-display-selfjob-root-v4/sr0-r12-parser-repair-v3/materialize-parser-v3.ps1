[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$CollectorPath,
  [Parameter(Mandatory)][string]$IdentitySourcePath,
  [Parameter(Mandatory)][string]$OutputRoot,
  [int64]$MaxSourceBytes = 2097152
)
$ErrorActionPreference='Stop'
if($MaxSourceBytes -lt 1 -or $MaxSourceBytes -gt 2097152){throw 'source bound rejected'}
function Require-SourceFile([string]$Path){
  $i=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $i.Length -gt $MaxSourceBytes){throw "source file rejected: $Path"}
  return $i
}
$collector=Require-SourceFile $CollectorPath
$identity=Require-SourceFile $IdentitySourcePath
if(Test-Path -LiteralPath $OutputRoot){throw "fresh output required: $OutputRoot"}
$collectorText=[IO.File]::ReadAllText($collector.FullName)
$identityText=[IO.File]::ReadAllText($identity.FullName)
if($identityText -notmatch '(?m)^function\s+Resolve-WorkloadIdentityV8\s*\{'){throw 'identity source lacks Resolve-WorkloadIdentityV8'}
if($identityText -notmatch 'Resolve-WorkloadIdentityV8Core'){throw 'identity source lacks V8 core'}
$v7=[regex]::Matches($collectorText,'\bResolve-WorkloadIdentityV7\b')
$v8=[regex]::Matches($collectorText,'\bResolve-WorkloadIdentityV8\b')
if($v7.Count -gt 1){throw "ambiguous V7 identity references: $($v7.Count)"}
if($v7.Count -eq 0 -and $v8.Count -eq 0){throw 'collector has no workload identity call'}
$rewritten=$collectorText
if($v7.Count -eq 1){$rewritten=[regex]::Replace($collectorText,'\bResolve-WorkloadIdentityV7\b','Resolve-WorkloadIdentityV8',1)}
if($rewritten -notmatch '\bResolve-WorkloadIdentityV8\b'){throw 'materialized collector lacks V8 identity call'}
[IO.Directory]::CreateDirectory($OutputRoot)|Out-Null
$outCollector=Join-Path $OutputRoot 'collector-selfjob-v8-crlf.ps1'
$outIdentity=Join-Path $OutputRoot 'workload-identity-v8-crlf.ps1'
[IO.File]::WriteAllText($outCollector,$rewritten,(New-Object Text.UTF8Encoding($false)))
[IO.File]::Copy($identity.FullName,$outIdentity)
$meta=[ordered]@{
  schema='sr0-r12-parser-materialization-v3'
  collectorSource=[IO.Path]::GetFullPath($collector.FullName)
  identitySource=[IO.Path]::GetFullPath($identity.FullName)
  collectorOutput=[IO.Path]::GetFullPath($outCollector)
  identityOutput=[IO.Path]::GetFullPath($outIdentity)
  replacement=[ordered]@{from='Resolve-WorkloadIdentityV7';to='Resolve-WorkloadIdentityV8';occurrences=[int]$v7.Count}
  sourceHashRefreshRequired=$true
  hashesMustBeSuppliedByRoot=@('collectorOutput','identityOutput')
  qualificationClaim=$false
}
$tmp=Join-Path $OutputRoot 'materialization.json.tmp'
[IO.File]::WriteAllText($tmp,($meta|ConvertTo-Json -Depth 8),(New-Object Text.UTF8Encoding($false)))
[IO.File]::Move($tmp,(Join-Path $OutputRoot 'materialization.json'))
$meta|ConvertTo-Json -Depth 8
