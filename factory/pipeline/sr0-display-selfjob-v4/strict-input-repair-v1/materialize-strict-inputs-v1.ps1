# Fresh adapter namespace for archived SR0 strict analysis inputs.
# Raw evidence stays untouched; missing build/incremental files are bound only from explicit receipts.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$RawRoot,
  [Parameter(Mandatory)][string]$BuildPath,
  [Parameter(Mandatory)][string]$IncrementalPath,
  [Parameter(Mandatory)][string]$OutputRoot,
  [Parameter(Mandatory)][string]$OutputPath,
  [int64]$MaxResultBytes=2097152,
  [int64]$MaxStreamBytes=8388608,
  [int64]$MaxCsvBytes=67108864,
  [int64]$MaxTraceBytes=33554432,
  [int64]$MaxTotalBytes=134217728
)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Hash([string]$Path){(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function InputFile([string]$Path,[int64]$Cap){
  Require (Test-Path -LiteralPath $Path -PathType Leaf) "input missing: $Path"
  $i=Get-Item -LiteralPath $Path -Force
  Require (($i.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) "reparse input rejected: $Path"
  Require ($i.Length -le $Cap) "input exceeds bound: $Path"
  return $i
}
function FreshFile([string]$Path,[byte[]]$Bytes){
  $full=[IO.Path]::GetFullPath($Path);Require (-not(Test-Path -LiteralPath $full)) "derived output exists: $full"
  $parent=Split-Path -Parent $full;if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null}
  $tmp="$full.$([Diagnostics.Process]::GetCurrentProcess().Id).$([guid]::NewGuid().ToString('N')).tmp"
  $s=[IO.File]::Open($tmp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  try{$s.Write($Bytes,0,$Bytes.Length);$s.Flush($true)}finally{$s.Dispose()}
  [IO.File]::Move($tmp,$full)
}
function FreshJson([string]$Path,[object]$Value){FreshFile $Path ([Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 16)+[Environment]::NewLine))}
function CopyFresh([IO.FileInfo]$Input,[string]$Output,[int64]$Cap,[ref]$Total){
  $i=InputFile $Input.FullName $Cap
  $Total.Value += [int64]$i.Length;Require ($Total.Value -le $MaxTotalBytes) 'derived input total exceeds bound'
  FreshFile $Output ([IO.File]::ReadAllBytes($i.FullName))
  return [ordered]@{path=$Output;bytes=[int64]$i.Length;sha256=(Hash $i.FullName);source=$i.FullName}
}
function ReadJson([string]$Path,[int64]$Cap){$i=InputFile $Path $Cap;return [IO.File]::ReadAllText($i.FullName)|ConvertFrom-Json}
$rawRootFull=[IO.Path]::GetFullPath($RawRoot);Require (Test-Path -LiteralPath $rawRootFull -PathType Container) "raw root missing: $rawRootFull"
$outRootFull=[IO.Path]::GetFullPath($OutputRoot);Require (-not(Test-Path -LiteralPath $outRootFull)) "output root must be fresh: $outRootFull";[IO.Directory]::CreateDirectory($outRootFull)|Out-Null
$total=[int64]0;$files=[ordered]@{}
$rawResult=CopyFresh (Join-Path $rawRootFull 'result-workload.txt') (Join-Path $outRootFull 'result-workload.txt') $MaxResultBytes ([ref]$total);$files.result=$rawResult
$rawCsv=CopyFresh (Join-Path $rawRootFull 'presentmon.csv') (Join-Path $outRootFull 'presentmon.csv') $MaxCsvBytes ([ref]$total);$files.presentmonCsv=$rawCsv
$rawOut=InputFile (Join-Path $rawRootFull 'presentmon.stdout.txt') $MaxStreamBytes
$rawErr=InputFile (Join-Path $rawRootFull 'presentmon.stderr.txt') $MaxStreamBytes
$total += [int64]$rawOut.Length + [int64]$rawErr.Length;Require ($total -le $MaxTotalBytes) 'derived input total exceeds bound'
$console=New-Object 'System.Collections.Generic.List[byte]';$buffer=New-Object byte[] 4096
foreach($src in @($rawOut,$rawErr)){
  $fs=[IO.File]::Open($src.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try{while(($n=$fs.Read($buffer,0,$buffer.Length)) -gt 0){for($j=0;$j -lt $n;$j++){[void]$console.Add($buffer[$j])}}}finally{$fs.Dispose()}
  if($src.FullName -eq $rawOut.FullName -and $console.Count -gt 0 -and $console[$console.Count-1] -ne 10){[void]$console.Add(13);[void]$console.Add(10)}
}
$consolePath=Join-Path $outRootFull 'presentmon.console.txt';FreshFile $consolePath ([byte[]]$console.ToArray())
$files.presentmonConsole=[ordered]@{path=$consolePath;bytes=[int64](Get-Item $consolePath).Length;sha256=(Hash $consolePath);source=@($rawOut.FullName,$rawErr.FullName)}
$buildInput=InputFile $BuildPath 2097152;$build=ReadJson $BuildPath 2097152
$incInput=InputFile $IncrementalPath 2097152;$inc=ReadJson $IncrementalPath 2097152
$exeSha=[string]$build.exe_sha256;if([string]::IsNullOrWhiteSpace($exeSha)){$exeSha=[string]$build.exeSha256}
$dllSha=[string]$build.dll_sha256;if([string]::IsNullOrWhiteSpace($dllSha)){$dllSha=[string]$build.dllSha256}
$manifestSha=[string]$build.sourceManifestSha256
Require ($exeSha -match '^[0-9a-fA-F]{64}$' -and $dllSha -match '^[0-9a-fA-F]{64}$') 'build artifact hashes missing'
Require ($manifestSha -match '^[0-9a-fA-F]{64}$') 'build source manifest hash missing'
Require ([string]$inc.source_manifest_sha256 -eq $manifestSha) 'incremental/source manifest mismatch'
Require ([string]$inc.source_file_sha256 -match '^[0-9a-fA-F]{64}$') 'incremental source hash missing'
$rawIdentity=[IO.File]::ReadAllText((Join-Path $outRootFull 'result-workload.txt'))
$rawExe=([regex]::Match($rawIdentity,'(?m)^exe=.*?exe_sha256=([0-9a-fA-F]{64})\s')).Groups[1].Value
$rawDll=([regex]::Match($rawIdentity,'(?m)^exe=.*?dll_sha256=([0-9a-fA-F]{64})\s')).Groups[1].Value
Require ($rawExe -and $rawDll) 'raw result artifact identity missing'
Require ($rawExe.ToLowerInvariant() -eq $exeSha.ToLowerInvariant() -and $rawDll.ToLowerInvariant() -eq $dllSha.ToLowerInvariant()) 'build artifact identity differs from captured workload'
$derivedBuild=[ordered]@{configuration='release';exe=[string]$build.exe;dll=[string]$build.dll;exe_sha256=$exeSha.ToLowerInvariant();dll_sha256=$dllSha.ToLowerInvariant();sourceManifestSha256=$manifestSha.ToLowerInvariant();source='explicit-build-receipt';sourcePath=$buildInput.FullName;sourceSha256=(Hash $buildInput.FullName);adapterDerived=$true}
FreshJson (Join-Path $outRootFull 'build.json') $derivedBuild
$incOut=Join-Path $outRootFull 'incremental.json';FreshFile $incOut ([IO.File]::ReadAllBytes($incInput.FullName))
$files.build=[ordered]@{path=(Join-Path $outRootFull 'build.json');bytes=[int64](Get-Item (Join-Path $outRootFull 'build.json')).Length;sha256=(Hash (Join-Path $outRootFull 'build.json'));source=$buildInput.FullName;sourceSha256=(Hash $buildInput.FullName)}
$files.incremental=[ordered]@{path=$incOut;bytes=[int64]$incInput.Length;sha256=(Hash $incInput.FullName);source=$incInput.FullName;sourceSha256=(Hash $incInput.FullName)}
$required=@('meta.json','integrity.json','inputs.csv','frames.csv','bridge_input.csv','ticks.csv','mainactor.csv','inject.csv','overhead_probe.csv')
foreach($name in $required){$src=InputFile (Join-Path $rawRootFull ('r1\'+$name)) $MaxTraceBytes;$dst=Join-Path (Join-Path $outRootFull 'r1') $name;$entry=CopyFresh $src $dst $MaxTraceBytes ([ref]$total);$files["r1/$name"]=$entry}
$resultText=$rawIdentity
$pidExit=[regex]::Matches($resultText,'(?m)^pid_exit run=\S+ pid=\d+ handle=[1-9]\d+ .* exit=-?\d+')
Require ($pidExit.Count -gt 0) 'raw result has no retained-handle pid_exit record'
$receipt=[ordered]@{kind='sr0-display-strict-input-repair-v1';status='materialized';qualificationHeld=$true;qualificationHoldReason='display-gate-and-metrics-remain-frozen';rawRoot=$rawRootFull;outputRoot=$outRootFull;rawPreserved=$true;parityClaim=$false;optionalHandleTailPreserved=$true;pidExitRecords=$pidExit.Count;buildInput=$buildInput.FullName;buildInputSha256=(Hash $buildInput.FullName);incrementalInput=$incInput.FullName;incrementalInputSha256=(Hash $incInput.FullName);sourceManifestSha256=$manifestSha.ToLowerInvariant();sourceFileSha256=([string]$inc.source_file_sha256).ToLowerInvariant();files=$files;totalDerivedBytes=$total;displayQualification='held';holdReasons=@('strict report originally refused missing console/build/incremental inputs; fresh adapter binds explicit receipts','raw report still has displayed-row, refresh, latency, & capture-integrity failures');createdAt=[DateTimeOffset]::UtcNow.ToString('o')}
FreshJson $OutputPath $receipt

