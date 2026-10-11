$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$base=Join-Path $repo '.work\sr0-r12-workload-v1';$stage=Join-Path $repo '.work\sr0-incremental-v9-evidence-r1';$zip=Join-Path $repo '.work\sr0-incremental-v9-evidence-r1.zip'
if((Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $zip)){throw 'Fresh export required'}
$receiptPath=Join-Path $base 'incremental.json'
if((Get-FileHash -LiteralPath $receiptPath).Hash.ToLowerInvariant() -cne 'e41bd6479dfb1dbac0867a85b43ba700b933b6c4e3bf14d9c38dbf0eb6c4126c'){throw 'Executed receipt drift'}
$r=[IO.File]::ReadAllText($receiptPath)|ConvertFrom-Json
if($r.kind -cne 'sr0-tuple12-ui-only-incremental-v9' -or -not $r.builds_ok -or -not $r.all_jobs_quiescent -or -not $r.source_restored -or -not $r.hashes_identical -or $r.rust_invocations_total -ne 0 -or @($r.trials).Count -ne 3){throw 'Completed receipt rejected'}
$runRoot=Join-Path $base ('incremental-runs\'+$r.run_id)
$pairs=@(@{source=$receiptPath;dest='incremental.json'},@{source=(Join-Path $base 'release-build-metadata-v6-r1.json');dest='release-build-metadata-v6-r1.json'},@{source=(Join-Path $base 'compiled-source-manifest.json');dest='compiled-source-manifest.json'},@{source=(Join-Path $runRoot 'shim\shim.log');dest='shim.log'})
foreach($t in $r.trials){
 if($t.kernel_wait -ne 0 -or $t.kernel_exit_code -ne 0 -or $t.dotnet_exit_code -ne 0 -or -not $t.streams_drained -or -not $t.streams_sealed -or -not $t.job_active_readable -or $t.job_active_processes -ne 0 -or $t.timeout -or $t.output_cap_exceeded){throw 'Trial terminal/stream/job proof rejected'}
 foreach($name in @('stdout','stderr')){$path=Join-Path $runRoot ('trials\edit-'+$t.edit+'.'+$name+'.txt');$i=Get-Item -LiteralPath $path;$hashKey=$name+'_sha256';$bytesKey=$name+'_bytes';if($i.Length -ne $t.$bytesKey -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $t.$hashKey){throw 'Trial sealed stream drift'};$pairs+=@{source=$path;dest=('trials/edit-'+$t.edit+'.'+$name+'.txt')}}
}
$sources=Join-Path $repo '.work\sr0-incremental-v9-controls-r1'
foreach($rel in @('stage-manifest.json','workload-incremental-v9\build-incremental-tuple12.ps1','workload-incremental-v9\README.md','workload-incremental-v9\source-pins.json','workload-incremental-v6\shared\Sr0OwnedJobProcess.cs')){$pairs+=@{source=(Join-Path $sources $rel);dest=('executed-source/'+$rel.Replace('\','/'))}}
[IO.Directory]::CreateDirectory($stage)|Out-Null;$rows=@();[long]$total=0
foreach($p in $pairs){$i=Get-Item -LiteralPath $p.source;if($i.Length -gt 8MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Export file bound'};$total+=$i.Length;if($total -gt 32MB){throw 'Export total bound'};$dest=Join-Path $stage $p.dest;[IO.Directory]::CreateDirectory((Split-Path $dest))|Out-Null;Copy-Item -LiteralPath $p.source -Destination $dest;$rows+=[ordered]@{path=$p.dest;bytes=$i.Length;sha256=(Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant()}}
$artifactRows=@();foreach($path in @($r.hashes_before.PSObject.Properties.Name,(Join-Path $base 'src\probes\sr0-b\workload\Sources\WorkloadCore\WorkloadScreen.swift'))){foreach($f in $path){$i=Get-Item -LiteralPath $f;if($i.Length -gt 32MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Artifact bound'};$artifactRows+=[ordered]@{path=$f;bytes=$i.Length;sha256=(Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant()}}}
$live=@(Get-Process swift,swiftc,swift-build,swift-frontend,clang -ErrorAction SilentlyContinue|ForEach-Object{[ordered]@{pid=$_.Id;name=$_.ProcessName;rssBytes=$_.WorkingSet64;session=$_.SessionId}})
$manifest=[ordered]@{kind='root-sr0-incremental-v9-export-v1';runID=$r.run_id;files=$rows;artifacts=$artifactRows;liveCompilers=$live;nativeActions=0;lockActions=0;deleted=$false}
[IO.File]::WriteAllText((Join-Path $stage 'manifest.json'),($manifest|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.IO.Compression.FileSystem;[IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip)
[ordered]@{zipPath=$zip;sha256=(Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $zip).Length;files=$rows.Count;rawBytes=$total;runID=$r.run_id;liveCompilerCount=$live.Count;nativeActions=0;lockActions=0;deleted=$false}|ConvertTo-Json
