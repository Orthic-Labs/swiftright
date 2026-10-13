$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$stage='D:\Claude\swiftright\.factory-work\hosts\text-baseline';$z=Join-Path $stage 'source-stage-r3.zip'
if((Get-Item $z).Length -gt 1MB -or (Get-FileHash $z).Hash.ToLowerInvariant() -cne 'a29920407398e837f701e4b77e572e082351ee27b9ea80a21cdf5de4f7197a93'){throw 'archive drift'}
$running=@(Get-CimInstance Win32_Process|Where-Object{$_.CommandLine -and $_.CommandLine.Contains($stage) -and $_.Name -like 'swift*'});if($running.Count){throw 'owned stage compiler active'}
if((Get-FileHash (Join-Path $stage 'package\Sources\FactoryProbe\Witness.swift')).Hash.ToLowerInvariant() -cne '7e946629be84134780d8742ce5eeea84ac2fb03860a1a0884027126772894dbe'){throw 'prior witness drift'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$a=[IO.Compression.ZipFile]::OpenRead($z)
try{foreach($entry in $a.Entries){$dest=Join-Path $stage $entry.FullName;$src=$entry.Open();$dst=[IO.File]::Open($dest,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None);try{$src.CopyTo($dst)}finally{$dst.Dispose();$src.Dispose()}}}finally{$a.Dispose()}
$mp=Join-Path $stage 'stage-manifest-r3.json';if((Get-FileHash $mp).Hash.ToLowerInvariant() -cne 'abdce97876f6618f9441986afd74abb93763b7d199f00509ad4374fc6b8f2bc6'){throw 'manifest drift'}
$m=Get-Content -Raw $mp|ConvertFrom-Json;foreach($row in $m.rows){$f=Join-Path $stage $row.path;if((Get-Item $f).Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'staged bytes drift'}}
& (Join-Path $stage 'build-text-r3.ps1') -PlanPath (Join-Path $stage 'package\plan-prebuild-r3.json') -PlanSha256 '801b58fbb2e5560d48c7573a396501bc10d10e443852888644081e5e1b0ecff6' -Phase prebuild -Attempt 3 -PreflightOnly
