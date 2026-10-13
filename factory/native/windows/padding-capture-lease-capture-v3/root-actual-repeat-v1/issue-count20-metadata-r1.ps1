$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$pkg='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3'
$pins=@'
[{"name": "issue-before-launch.ps1", "sha256": "6d8ade4a46e4264af381543099f1474be3dabee5171e062389277e784ad0de35"}, {"name": "support/integration.ps1", "sha256": "238b0df7a4f517babbbb2cb32133a2e4890ccb3b23839cd3dbdf5ae171270de4"}, {"name": "root-metadata-controls-v1/test-metadata-guard-controls.ps1", "sha256": "4b6d832b1503113890103651fc0e2503eb6192bf9713a94bab932d3c3776e746"}]
'@|ConvertFrom-Json
foreach($r in $pins){$p=Join-Path $pkg $r.name;if((Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant() -cne $r.sha256){throw ('metadata source drift '+$r.name)}}
$CompileHash='1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf';$ExeHash='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a';$SerializerHash='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
$control=Join-Path $pkg 'coordinator-repeat-r1';$run=Join-Path $pkg 'actual-repeat-r1';$issued=Join-Path $control 'issued-metadata.json'
if((Test-Path -LiteralPath $control) -or (Test-Path -LiteralPath $run)){throw 'Exclusive Count20 namespace already exists'}
[IO.Directory]::CreateDirectory($control)|Out-Null
& (Join-Path $pkg 'issue-before-launch.ps1') -Count 20 -RunRoot $run -OutputPath $issued -CompileReceiptSha256 $CompileHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerHash
$issuedHash=(Get-FileHash -LiteralPath $issued).Hash.ToLowerInvariant();$actual=Join-Path $pkg 'root-actual-repeat-v1';if(Test-Path -LiteralPath $actual){throw 'Exclusive metadata controls root exists'};[IO.Directory]::CreateDirectory($actual)|Out-Null
& (Join-Path $pkg 'root-metadata-controls-v1\test-metadata-guard-controls.ps1') -IssuedMetadataPath $issued -IssuedMetadataHash $issuedHash -RunRoot $run -Count 20 -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash -ProducerRoot $pkg -ControlRoot (Join-Path $actual 'controls-r1') -OutputPath (Join-Path $actual 'metadata-controls-r1.json')
$files=@();foreach($f in Get-ChildItem -LiteralPath $control,$actual -File -Recurse){$files+=@{path=$f.FullName.Substring($pkg.Length+1).Replace('\','/');recordedPath=$f.FullName;bytes=$f.Length;sha256=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant()}}
$z='D:\Claude\swiftright\.factory-work\transports\count20-metadata-r1.zip';if(Test-Path -LiteralPath $z){throw 'Archive already exists'}
Add-Type -AssemblyName System.IO.Compression;$s=[IO.File]::Open($z,[IO.FileMode]::CreateNew);$arc=New-Object IO.Compression.ZipArchive($s,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($f in $files){$b=[IO.File]::ReadAllBytes($f.recordedPath);$entry=$arc.CreateEntry($f.path);$stream=$entry.Open();try{$stream.Write($b,0,$b.Length)}finally{$stream.Dispose()}};$doc=[Text.Encoding]::UTF8.GetBytes((@{files=$files;nativeActions=0;lockActions=0}|ConvertTo-Json -Depth 10));$stream=$arc.CreateEntry('manifest.json').Open();try{$stream.Write($doc,0,$doc.Length)}finally{$stream.Dispose()}}finally{$arc.Dispose();$s.Dispose()}
@{kind='root-count20-prelaunch-issued-and-full-guard-v1';nativeActions=0;lockActions=0;issuedMetadataHash=$issuedHash;guardHash=(Get-FileHash -LiteralPath (Join-Path $actual 'metadata-controls-r1.json')).Hash.ToLowerInvariant();zipPath=$z;bytes=(Get-Item -LiteralPath $z).Length;sha256=(Get-FileHash -LiteralPath $z).Hash.ToLowerInvariant()}|ConvertTo-Json
