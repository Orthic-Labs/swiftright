# Bounded UIA producer-source closure admission. No lock, process, or native action.
Set-StrictMode -Version Latest

function Get-UiaClosureItem([string]$Path,[int64]$Limit=67108864){
 if([string]::IsNullOrWhiteSpace($Path)){throw 'UIA source path missing'}
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if($item.PSIsContainer -or $item.LinkType -or (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or $item.Length -gt $Limit){throw ('UIA source must be bounded regular non-reparse file: '+$Path)}
 return $item
}
function Get-UiaClosureHash([string]$Path,[int64]$Limit=67108864){
 $item=Get-UiaClosureItem $Path $Limit;$stream=$null;$sha=$null;$total=0L
 try{
  $stream=[IO.File]::Open($item.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $sha=[Security.Cryptography.SHA256]::Create();$buffer=New-Object byte[] 1048576
  while(($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0){$sha.TransformBlock($buffer,0,$read,$buffer,0)|Out-Null;$total+=$read;if($total -gt $Limit){throw 'UIA source hash limit exceeded'}}
  $sha.TransformFinalBlock($buffer,0,0)|Out-Null
  if($total -ne [int64]$item.Length){throw ('UIA source changed while hashing: '+$Path)}
  return ([BitConverter]::ToString($sha.Hash)-replace '-','').ToLowerInvariant()
 }finally{if($null -ne $sha){$sha.Dispose()};if($null -ne $stream){$stream.Dispose()}}
}
function Read-UiaClosureJson([string]$Path){
 $item=Get-UiaClosureItem $Path 2097152
 return [IO.File]::ReadAllText($item.FullName,[Text.UTF8Encoding]::new($false))|ConvertFrom-Json
}
function Assert-UiaClosureRelative([string]$Path){
 if([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or $Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path -match '(^|[\\/]):' -or $Path.StartsWith('/') -or $Path.StartsWith('\')){throw ('UIA source path must be relative and contained: '+$Path)}
 return (($Path -replace '\\','/').TrimStart('./'))
}
function Assert-UiaClosureInside([string]$Root,[string]$Relative){
 $rootFull=([IO.Path]::GetFullPath($Root)).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
 $candidate=[IO.Path]::GetFullPath((Join-Path $rootFull $Relative))
 if(-not $candidate.StartsWith($rootFull+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw ('UIA source path escapes producer root: '+$Relative)}
 return $candidate
}
function Assert-UiaClosurePath([string]$Root,[string]$Relative,[int64]$Bytes,[string]$ExpectedHash){
 $normalized=Assert-UiaClosureRelative $Relative;$path=Assert-UiaClosureInside $Root $normalized;$item=Get-UiaClosureItem $path
 if($item.Length -ne [int64]$Bytes){throw ('UIA source byte count drift: '+$Relative)}
 $actual=Get-UiaClosureHash $path
 $expected=(([string]$ExpectedHash)-replace '^sha256:','').ToLowerInvariant()
 if($expected -notmatch '^[0-9a-f]{64}$' -or $actual -cne $expected){throw ('UIA source hash drift: '+$Relative)}
 [ordered]@{path=$normalized;absolutePath=$path;bytes=[int64]$item.Length;sha256=$actual}
}
function Assert-FactoryUiaSourceClosure {
 param(
  [Parameter(Mandatory=$true)][string]$ProducerRoot,
  [Parameter(Mandatory=$true)][string]$WorkerSourceRoot,
  [Parameter(Mandatory=$true)][string]$WorkerContractPath,
  [Parameter(Mandatory=$true)][string]$IntegrationBindingsPath,
  [Parameter(Mandatory=$true)][int64]$IntegrationBindingsBytes,
  [Parameter(Mandatory=$true)][string]$IntegrationBindingsHash,
  [Parameter(Mandatory=$true)][object]$SourceBindings,
  [switch]$RequireMtaInvoker
 )
 $producer=[IO.Path]::GetFullPath($ProducerRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
 $source=[IO.Path]::GetFullPath($WorkerSourceRoot).TrimEnd([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
 if(-not $source.StartsWith($producer+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'UIA worker source root outside producer root'}
 $integrationItem=Get-UiaClosureItem $IntegrationBindingsPath 2097152
 if($integrationItem.Length -ne $IntegrationBindingsBytes){throw 'UIA integration binding byte count drift'}
 if((Get-UiaClosureHash $IntegrationBindingsPath) -cne (([string]$IntegrationBindingsHash)-replace '^sha256:','').ToLowerInvariant()){throw 'UIA integration binding hash drift'}
 $integration=Read-UiaClosureJson $IntegrationBindingsPath
 if($null -eq $integration.files){throw 'UIA integration binding files missing'}
 $rows=@($integration.files);if($rows.Count -eq 0 -or $rows.Count -gt 512){throw 'UIA integration binding row count out of bounds'};$rowMap=@{};$totalBytes=0L
 foreach($row in $rows){
  $relative=Assert-UiaClosureRelative ([string]$row.path)
  if($row.bytes -lt 0 -or [string]$row.sha256 -notmatch '^[0-9a-f]{64}$' -or $rowMap.ContainsKey($relative)){throw ('UIA integration binding row invalid or duplicated: '+$relative)};$totalBytes+=[int64]$row.bytes;if($totalBytes -gt 1073741824){throw 'UIA integration binding total exceeds 1 GiB'}
  $rowMap[$relative]=[ordered]@{bytes=[int64]$row.bytes;sha256=[string]$row.sha256}
  [void](Assert-UiaClosurePath $producer $relative ([int64]$row.bytes) ([string]$row.sha256))
 }
 $contractFull=[IO.Path]::GetFullPath($WorkerContractPath)
 if(-not $contractFull.StartsWith($producer+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'UIA worker contract outside producer root'}
 $contractRelative=(($contractFull.Substring($producer.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar))-replace '\\','/')
 $contractItem=Get-UiaClosureItem $contractFull 2097152
 if(-not $rowMap.ContainsKey($contractRelative)){throw 'UIA worker contract integration row missing'}
 $contractRow=$rowMap[$contractRelative]
 if($contractItem.Length -ne [int64]$contractRow.bytes -or (Get-UiaClosureHash $contractFull) -cne [string]$contractRow.sha256){throw 'UIA worker contract bytes/hash drift'}
 $contract=Read-UiaClosureJson $contractFull
 if($null -eq $contract.sourceBindings){throw 'UIA worker contract sourceBindings missing'}
 $contractBindings=@($contract.sourceBindings);$bindings=@($SourceBindings);if($bindings.Count -eq 0 -or $bindings.Count -gt 128 -or $contractBindings.Count -ne $bindings.Count){throw 'UIA source bindings empty or contract mismatch'}
 foreach($contractBinding in $contractBindings){$matches=@($bindings|Where-Object{[string]$_.path -ceq [string]$contractBinding.path -and [string]$_.sha256 -ceq [string]$contractBinding.sha256 -and [int64]$_.bytes -eq [int64]$contractBinding.bytes});if($matches.Count -ne 1){throw ('UIA worker contract/source binding mismatch: '+[string]$contractBinding.path)}}
 $seen=@{};$admitted=@()
 foreach($binding in $bindings){
  $relative=Assert-UiaClosureRelative ([string]$binding.path)
  if($seen.ContainsKey($relative)){throw ('UIA worker source binding duplicated: '+$relative)};$seen[$relative]=$true
  if($binding.bytes -lt 0 -or [string]$binding.sha256 -notmatch '^[0-9a-f]{64}$'){throw ('UIA worker source binding malformed: '+$relative)}
  $workerPath=Assert-UiaClosurePath $source $relative ([int64]$binding.bytes) ([string]$binding.sha256)
  $integrationRelative=($source.Substring($producer.Length).TrimStart([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)-replace '\\','/')+'/'+$relative
  if(-not $rowMap.ContainsKey($integrationRelative)){throw ('UIA worker source missing integration row: '+$integrationRelative)}
  $row=$rowMap[$integrationRelative];if($row.bytes -ne [int64]$binding.bytes -or $row.sha256 -cne [string]$binding.sha256){throw ('UIA worker source integration mismatch: '+$relative)}
  $admitted+=@($workerPath)
 }
 if($RequireMtaInvoker){$mta=@($bindings|Where-Object{([string]$_.path)-ceq 'invoke-worker-mta.ps1'});if($mta.Count -ne 1){throw 'UIA MTA invoker source binding missing'}}
 [ordered]@{kind='factory-uia-source-closure-admission-v1';producerRoot=$producer;workerSourceRoot=$source;integrationBindingsPath=$IntegrationBindingsPath;integrationBindingsHash=(Get-UiaClosureHash $IntegrationBindingsPath);sourceCount=$bindings.Count;sourceBindings=$admitted;requireMtaInvoker=[bool]$RequireMtaInvoker;nativeActions=0;compilerActions=0}
}
