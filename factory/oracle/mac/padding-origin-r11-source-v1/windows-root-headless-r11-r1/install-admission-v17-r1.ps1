$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$ns=Join-Path $repo 'factory\native\windows\.work\windows-replay-r11\r17';$stage=Join-Path $ns 'overlay';$producer=Join-Path $repo 'factory\native\windows\padding-capture-lease-capture-v3'
function Read-BoundedJson([string]$p){$i=Get-Item -LiteralPath $p;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe JSON input'};[IO.File]::ReadAllText($p)|ConvertFrom-Json}
$schema=Join-Path $ns 'mac-schema-r1';$zip=Join-Path $repo '.factory-work\windows-replay-r11-mac-schema-v17-r1.zip'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'b6c1724e00ded57dc7863d5c967452045a97a5c55ecc1c8cc4cc1a0017bb0bf7'){throw 'Schema ZIP drift'};if(Test-Path -LiteralPath $schema){throw 'Fresh schema stage required'};Expand-Archive -LiteralPath $zip -DestinationPath $schema
$sm=Read-BoundedJson (Join-Path $schema 'stage-manifest.json');foreach($r in $sm.files){$f=Join-Path $schema $r.path;if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Schema source drift'}}
$control=Join-Path $ns 'coordinator-r1';$schema=Join-Path $ns 'mac-schema-r1';$headless=Join-Path $ns 'admission-controls-v17-r1';if(Test-Path -LiteralPath $headless){throw 'Fresh control output required'};[IO.Directory]::CreateDirectory($headless)|Out-Null
$legacy=Read-BoundedJson (Join-Path $producer 'coordinator-single-r1\issued-metadata.json');$context=Read-BoundedJson $legacy.candidateContext.path
$stale=Join-Path $headless 'stale-repo';[IO.Directory]::CreateDirectory($stale)|Out-Null;$staleFirst=$null;$refs=@($context.macContext.sourceRefs)
if($refs.Count -lt 3 -or $refs.Count -gt 32){throw 'Bounded Count1 raw joins required'}
foreach($r in $refs){if([IO.Path]::IsPathRooted($r.path)){throw 'Expected repository-relative Count1 join'};$s=[IO.Path]::GetFullPath((Join-Path $repo $r.path));$d=[IO.Path]::GetFullPath((Join-Path $stale $r.path));if(-not $s.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or -not $d.StartsWith($stale+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Raw ref escaped root'};$i=Get-Item -LiteralPath $s;if($i.Length -gt 2MB -or $i.Length -ne $r.bytes -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ('sha256:'+(Get-FileHash -LiteralPath $s).Hash.ToLowerInvariant()) -cne $r.sha256){throw 'Canonical Count1 raw drift'};[IO.Directory]::CreateDirectory((Split-Path -Parent $d))|Out-Null;Copy-Item -LiteralPath $s -Destination $d;if(-not $staleFirst){$staleFirst=$d}}
[IO.File]::AppendAllText($staleFirst,' ',[Text.UTF8Encoding]::new($false))
$cfg=[ordered]@{
 coordinatorPath=(Join-Path $stage 'resume-issued-coordinator-fresh-r11-v17.ps1');coordinatorSha256='2732867535c50f418dfcd13c5ec632622efb0ca38a44289b6233bed5f4d8b7fa'
 compileReceiptHash='1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf';exeHash='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a';serializerControlSha256='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
 issuedMetadataPath=(Join-Path $control 'issued-metadata.json');issuedMetadataHash='876611d051d5f9af06e87d52c148da7df5fd37381caebf4e2c2caea4935e4adf'
 guardControlsPath=(Join-Path $ns '.factory-work\controls-full-r1\metadata-controls.json');guardControlsHash='3c12b76c053bae560c14781eeb800c4cec3c2af49e8e92b1fbbb68e33c17c8f2'
 freshGuardControlsPath=(Join-Path $control 'fresh-guard.json');freshGuardControlsHash='ce5bb0386aa00180f4a81969cb77d31ffd7f53494eb2c6d122b0366f8444abcc'
 macSchemaReceiptPath=(Join-Path $schema 'mac-schema-receipt.json');macSchemaReceiptHash='d38031b5474a72fddd7e50e1635620ad12994637ed250225d19d3a94cc45a42e'
 producerRoot=$producer;controlRoot=$control;runRoot=(Join-Path $ns 'replays\r1');outputRoot=(Join-Path $ns 'replays')
 integrationGuardPath=(Join-Path $stage 'integration-fresh-r11-v7.ps1');integrationGuardHash='4e7bac792ab47d7acc35795262edb7c75cae36d7749a0bedc85814d814d76e98';schemaPath=(Join-Path $schema 'common.schema.json')
 admissionRoot=$repo;wrongAdmissionRoot=$producer;missingAdmissionRoot=(Join-Path $headless 'does-not-exist');staleAdmissionRoot=$stale
}
$cfgPath=Join-Path $headless 'config.json';[IO.File]::WriteAllText($cfgPath,($cfg|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$result=& (Join-Path $stage 'test-first-proof-admission-v12.ps1') -ConfigPath $cfgPath
$out=Join-Path $headless 'admission-controls.json';[IO.File]::WriteAllText($out,($result -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false));$r=Read-BoundedJson $out
if($r.status -cne 'passed-source-only' -or @($r.controls).Count -ne 4 -or @($r.controls|Where-Object{$_.accepted}).Count -ne 1 -or -not $r.controls[0].accepted){throw 'Actual admission controls rejected'}
[ordered]@{kind='root-factory-admission-v17-stage-v1';status='passed-source-only';parsed=10;controls=$r;controlReceiptSha256=(Get-FileHash -LiteralPath $out).Hash.ToLowerInvariant();nativeWindowActions=0;compilerActions=0;guiActions=0;lockActions=0;at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12

# Admit complete inner capture path headlessly, including frozen Count1 raw joins.
$dp=@{}
foreach($key in @('ProducerRoot','AdmissionRoot','ControlRoot','OutputRoot','IntegrationGuardPath','IntegrationGuardHash','FreshGuardControlsPath','FreshGuardControlsHash','CompileReceiptHash','ExeHash','SerializerControlSha256','RunRoot','IssuedMetadataPath','IssuedMetadataHash')){$dp[$key]=$cfg.$key}
& (Join-Path $stage 'dispatch-fresh-r11-v17.ps1') @dp -LockOwner 'root-headless-preflight-only' -Count 20 -PreflightOnly
$deep=Read-BoundedJson (Join-Path $control 'capture-preflight.json')
if($deep.kind -cne 'factory-native-overlay-prelaunch-v17' -or $deep.issuedMetadataHash -cne $cfg.issuedMetadataHash -or $deep.nativeWindowActions -ne 0 -or $deep.guiActions -ne 0 -or $deep.lockActions -ne 0){throw 'Deep native admission rejected'}
$mr=Join-Path $ns 'memory-controls-v17-r1.json'
& (Join-Path $stage 'test-memory-bound-controls-v15.ps1') -SourcePath (Join-Path $stage 'Sr0OwnedJobProcess-v15.cs') -ControlRoot (Join-Path $ns 'memory-controls-v17-r1') -Output $mr
$mc=Read-BoundedJson $mr;if($mc.jobMemoryLimitBytes -ne 1073741824 -or $mc.jobMemoryLimitFlag -ne 512 -or @($mc.controls).Count -ne 4 -or -not $mc.childProof.terminal -or -not $mc.childProof.originalHandleRetained){throw 'Actual memory controls rejected'}
[ordered]@{kind='root-factory-v17-deep-memory-admission-v1';status='passed';issuedMetadataHash=$cfg.issuedMetadataHash;memoryControlsSha256=(Get-FileHash -LiteralPath $mr).Hash.ToLowerInvariant();stageManifestSha256=(Get-FileHash -LiteralPath (Join-Path $stage 'stage-manifest.json')).Hash.ToLowerInvariant();nativeWindowActions=0;guiActions=0;lockActions=0;deep=$deep;memory=$mc}|ConvertTo-Json -Depth 12
