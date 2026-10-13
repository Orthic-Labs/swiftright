$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$ns=Join-Path $repo '.factory-work\windows-replay-r11\r14';$stage=Join-Path $ns 'overlay';$producer=Join-Path $repo 'factory\native\windows\padding-capture-lease-capture-v3'
function Read-BoundedJson([string]$p){$i=Get-Item -LiteralPath $p;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe JSON input'};[IO.File]::ReadAllText($p)|ConvertFrom-Json}
$schema=Join-Path $ns 'mac-schema-r1';$zip=Join-Path $repo '.factory-work\windows-replay-r11-mac-schema-v14-r1.zip'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'c555b918874d3589e4adbeda3f152cae4151bd19d06fcdc8bc8740ebebc7df38'){throw 'Schema ZIP drift'};if(Test-Path -LiteralPath $schema){throw 'Fresh schema stage required'};Expand-Archive -LiteralPath $zip -DestinationPath $schema
$sm=Read-BoundedJson (Join-Path $schema 'stage-manifest.json');foreach($r in $sm.files){$f=Join-Path $schema $r.path;if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Schema source drift'}}
$control=Join-Path $ns 'coordinator-r1';$schema=Join-Path $ns 'mac-schema-r1';$headless=Join-Path $ns 'admission-controls-v14-r1';if(Test-Path -LiteralPath $headless){throw 'Fresh control output required'};[IO.Directory]::CreateDirectory($headless)|Out-Null
$legacy=Read-BoundedJson (Join-Path $producer 'coordinator-single-r1\issued-metadata.json');$context=Read-BoundedJson $legacy.candidateContext.path
$stale=Join-Path $headless 'stale-repo';[IO.Directory]::CreateDirectory($stale)|Out-Null;$staleFirst=$null;$refs=@($context.macContext.sourceRefs)
if($refs.Count -lt 3 -or $refs.Count -gt 32){throw 'Bounded Count1 raw joins required'}
foreach($r in $refs){if([IO.Path]::IsPathRooted($r.path)){throw 'Expected repository-relative Count1 join'};$s=[IO.Path]::GetFullPath((Join-Path $repo $r.path));$d=[IO.Path]::GetFullPath((Join-Path $stale $r.path));if(-not $s.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or -not $d.StartsWith($stale+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Raw ref escaped root'};$i=Get-Item -LiteralPath $s;if($i.Length -gt 2MB -or $i.Length -ne $r.bytes -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ('sha256:'+(Get-FileHash -LiteralPath $s).Hash.ToLowerInvariant()) -cne $r.sha256){throw 'Canonical Count1 raw drift'};[IO.Directory]::CreateDirectory((Split-Path -Parent $d))|Out-Null;Copy-Item -LiteralPath $s -Destination $d;if(-not $staleFirst){$staleFirst=$d}}
[IO.File]::AppendAllText($staleFirst,' ',[Text.UTF8Encoding]::new($false))
$cfg=[ordered]@{
 coordinatorPath=(Join-Path $stage 'resume-issued-coordinator-fresh-r11-v12.ps1');coordinatorSha256='3a7ac26fe08db538ab6708d2caaf0125d904752debdac9a53dcd3fa8ed567172'
 compileReceiptHash='1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf';exeHash='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a';serializerControlSha256='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
 issuedMetadataPath=(Join-Path $control 'issued-metadata.json');issuedMetadataHash='d8ac2784cce18a01e2f937503022aaa42414744e48a389abc9b507bd7d5a8b7c'
 guardControlsPath=(Join-Path $ns 'controls-full-r1\metadata-controls.json');guardControlsHash='daac21206b39bb98d20fdcec076693bc5957f63e04e32d9ad5881c1ac011b3d3'
 freshGuardControlsPath=(Join-Path $control 'fresh-guard.json');freshGuardControlsHash='64c092ee1f43262a81562c04c36b8321214e0627ad7e864efd1f45a1fe78207b'
 macSchemaReceiptPath=(Join-Path $schema 'mac-schema-receipt.json');macSchemaReceiptHash='714f5b257d0334786e4d225b1ed5cde99981fb29e8eec8e6846503d1d94d7596'
 producerRoot=$producer;controlRoot=$control;runRoot=(Join-Path $ns 'replays\r1');outputRoot=(Join-Path $ns 'replays')
 integrationGuardPath=(Join-Path $stage 'integration-fresh-r11-v7.ps1');integrationGuardHash='4e7bac792ab47d7acc35795262edb7c75cae36d7749a0bedc85814d814d76e98';schemaPath=(Join-Path $schema 'common.schema.json')
 admissionRoot=$repo;wrongAdmissionRoot=$producer;missingAdmissionRoot=(Join-Path $headless 'does-not-exist');staleAdmissionRoot=$stale
}
$cfgPath=Join-Path $headless 'config.json';[IO.File]::WriteAllText($cfgPath,($cfg|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$result=& (Join-Path $stage 'test-first-proof-admission-v12.ps1') -ConfigPath $cfgPath
$out=Join-Path $headless 'admission-controls.json';[IO.File]::WriteAllText($out,($result -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false));$r=Read-BoundedJson $out
if($r.status -cne 'passed-source-only' -or @($r.controls).Count -ne 4 -or @($r.controls|Where-Object{$_.accepted}).Count -ne 1 -or -not $r.controls[0].accepted){throw 'Actual admission controls rejected'}
[ordered]@{kind='root-factory-admission-v14-stage-v1';status='passed-source-only';parsed=10;controls=$r;controlReceiptSha256=(Get-FileHash -LiteralPath $out).Hash.ToLowerInvariant();nativeWindowActions=0;compilerActions=0;guiActions=0;lockActions=0;at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12
