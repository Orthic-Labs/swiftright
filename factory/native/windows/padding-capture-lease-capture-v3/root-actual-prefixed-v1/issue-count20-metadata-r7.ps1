$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$pkg='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3';$control=Join-Path $pkg 'coordinator-repeat-r1\coordinator.json'
if((Get-FileHash -LiteralPath $control).Hash.ToLowerInvariant() -cne '2c262f80c7ef81d0afcfcff8fd2f3df33321f80e989e845f31112c76e16f92c0'){throw 'ArchivedCount20terminaldrift'}
$c=Get-Content -Raw -LiteralPath $control|ConvertFrom-Json;if(-not$c.lockReleased -or -not$c.wholeBatchExitConfirmed -or $c.cleanupErrors.Count){throw 'Ownedexits notconfirmed'}
$tasks=@(Get-ScheduledTask -TaskName $c.taskName);if($tasks.Count -ne 1 -or $tasks[0].State -in @('Running','Queued')){throw 'Originaltasknonquiescent'}
$exe='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\build-capture-lease-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe';$busy=@(Get-CimInstance Win32_Process|Where-Object{$_.ExecutablePath -ieq $exe -or ($_.CommandLine -like '*padding-capture-lease-capture-v3*' -and $_.CommandLine -match '(interactive-task-repeat-r6\.ps1|dispatch-repeat-r6\.ps1|capture-repeat-r6\.ps1)')});if($busy.Count){throw 'Originalexactownedprocessactive'}
if(([IO.File]::ReadAllText('D:\Claude\desktop.lock')).Trim() -cne 'free'){throw 'Desktoplocknotfree'}
$dest='D:\Claude\swiftright\.factory-work\retired\native20-preflight-r6';if(Test-Path -LiteralPath $dest){throw 'Retirementtargetexists'};[IO.Directory]::CreateDirectory($dest)|Out-Null
$moves=@();foreach($n in @('actual-repeat-r1','coordinator-repeat-r1')){$src=Join-Path $pkg $n;if(Test-Path -LiteralPath $src){$to=Join-Path $dest $n;Move-Item -LiteralPath $src -Destination $to;$moves+=@{source=$src;destination=$to;deleted=$false}}}
@{status='moved-after-verified-Mac-archive';moves=$moves;ownedProcesses=0;deleted=$false;nativeActions=0}|ConvertTo-Json -Depth 8

$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$pkg='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3';$staged='D:\Claude\swiftright\.factory-work\transports\test-metadata-guard-controls-r4.ps1';$helper=Join-Path $pkg 'root-metadata-controls-v1\execute-r4\test-metadata-guard-controls-r4.ps1'
if((Get-FileHash -LiteralPath $helper).Hash.ToLowerInvariant() -cne 'b3504ffbd02ad05f4a605e53ab7bcbb58e465da251b94d18d296931eefea351e'){throw 'guard helper drift'}
$issuer=Join-Path $pkg 'root-metadata-controls-v1\issuer-overlay-r1\issue-before-launch-prefixed-r1.ps1';if((Get-FileHash -LiteralPath $issuer).Hash.ToLowerInvariant() -cne 'ee30fdd3f83459a62a2024fe95b22bf228b1471cf7498642181e49c2d473d66e'){throw 'issuer source drift'}
$CompileHash='1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf';$ExeHash='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a';$SerializerHash='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
$out=Join-Path $pkg 'root-actual-prefixed-count20-r7';if(Test-Path -LiteralPath $out){throw 'fresh prefixedcontrols rootrequired'};[IO.Directory]::CreateDirectory($out)|Out-Null
$results=@()
foreach($count in @(20)){
 $lane=if($count -eq 1){'single'}else{'repeat'};$control=Join-Path $pkg ('coordinator-'+$lane+'-r1');$run=Join-Path $pkg ('actual-'+$lane+'-r1');$issued=Join-Path $control 'issued-metadata.json'
 if((Test-Path -LiteralPath $control) -or (Test-Path -LiteralPath $run)){throw 'originalrejected metadata notretired'};[IO.Directory]::CreateDirectory($control)|Out-Null
 & $issuer -Count $count -RunRoot $run -OutputPath $issued -CompileReceiptSha256 $CompileHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerHash|Out-Null
 $issuedHash=(Get-FileHash -LiteralPath $issued).Hash.ToLowerInvariant();$guardOut=Join-Path $out ('metadata-controls-count'+$count+'-r1.json')
 & $helper -IssuedMetadataPath $issued -IssuedMetadataHash $issuedHash -RunRoot $run -Count $count -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash -ProducerRoot $pkg -ControlRoot (Join-Path $out ('controls-count'+$count+'-r1')) -OutputPath $guardOut|Out-Null
 $results+=@{count=$count;issuedMetadataPath=$issued;issuedMetadataSha256=$issuedHash;guardPath=$guardOut;guardSha256=(Get-FileHash -LiteralPath $guardOut).Hash.ToLowerInvariant()}
}
$refs=@();foreach($name in @('coordinator-repeat-r1','root-actual-prefixed-count20-r7')){foreach($f in Get-ChildItem -LiteralPath (Join-Path $pkg $name) -File -Recurse){$refs+=@{path=$f.FullName.Substring($pkg.Length+1).Replace('\','/');recordedPath=$f.FullName;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant()}}}
$zipPath='D:\Claude\swiftright\.factory-work\transports\prefixed-count20-metadata-r7.zip';if(Test-Path -LiteralPath $zipPath){throw 'fresh metadataarchive required'};Add-Type -AssemblyName System.IO.Compression;$s=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew);$arc=New-Object IO.Compression.ZipArchive($s,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($f in $refs){$b=[IO.File]::ReadAllBytes($f.recordedPath);$st=$arc.CreateEntry($f.path).Open();try{$st.Write($b,0,$b.Length)}finally{$st.Dispose()}};$b=[Text.Encoding]::UTF8.GetBytes((@{kind='root-prefixed-canonical-prelaunch-metadata-fetch-v1';files=$refs;results=$results;nativeActions=0;lockActions=0}|ConvertTo-Json -Depth 10));$st=$arc.CreateEntry('manifest.json').Open();try{$st.Write($b,0,$b.Length)}finally{$st.Dispose()}}finally{$arc.Dispose();$s.Dispose()}
@{kind='root-prefixed-canonical-prelaunch-metadata-terminal-v1';results=$results;zipPath=$zipPath;sha256=(Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $zipPath).Length;nativeActions=0;lockActions=0}|ConvertTo-Json -Depth 10
