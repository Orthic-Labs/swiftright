$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$ns=Join-Path $repo '.factory-work\windows-replay-r11';$stage=Join-Path $ns 'overlay-v11';$zip=Join-Path $repo '.factory-work\windows-replay-r11-overlay-v11.zip';$producer=Join-Path $repo 'factory\native\windows\padding-capture-lease-capture-v3'
function Read-BoundedJson([string]$p){$i=Get-Item -LiteralPath $p;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Unsafe JSON input'};[IO.File]::ReadAllText($p)|ConvertFrom-Json}
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne '0acb5f2cca188740fc6bcdf5a9e8349a0c57bd2cfaccc152504004a4f6ad044e'){throw 'ZIP drift'}
if(-not(Test-Path -LiteralPath $stage)){Expand-Archive -LiteralPath $zip -DestinationPath $stage}
$m=Read-BoundedJson (Join-Path $stage 'stage-manifest.json');$parsed=0
foreach($r in $m.files){$f=Join-Path $stage $r.path;$i=Get-Item -LiteralPath $f;if($i.Length -ne $r.bytes -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Stage drift'};$t=$null;$e=$null;$null=[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$t,[ref]$e);if($e.Count){throw ('Source parse failed '+$r.path+': '+($e.Message -join ';'))};$parsed++}
if(@(Get-ChildItem -LiteralPath $stage -File -Force).Count -ne (@($m.files).Count+1)){throw 'Stage inventory mismatch'}
$control=Join-Path $ns 'coordinator-r1';$schema=Join-Path $ns 'mac-schema-r2';$headless=Join-Path $ns 'admission-controls-v11-r2';if(Test-Path -LiteralPath $headless){throw 'Fresh control output required'};[IO.Directory]::CreateDirectory($headless)|Out-Null
$legacy=Read-BoundedJson (Join-Path $producer 'coordinator-single-r1\issued-metadata.json');$context=Read-BoundedJson $legacy.candidateContext.path
$stale=Join-Path $headless 'stale-repo';[IO.Directory]::CreateDirectory($stale)|Out-Null;$staleFirst=$null;$refs=@($context.macContext.sourceRefs)
if($refs.Count -lt 3 -or $refs.Count -gt 32){throw 'Bounded Count1 raw joins required'}
foreach($r in $refs){if([IO.Path]::IsPathRooted($r.path)){throw 'Expected repository-relative Count1 join'};$s=[IO.Path]::GetFullPath((Join-Path $repo $r.path));$d=[IO.Path]::GetFullPath((Join-Path $stale $r.path));if(-not $s.StartsWith($repo+'\',[StringComparison]::OrdinalIgnoreCase) -or -not $d.StartsWith($stale+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Raw ref escaped root'};$i=Get-Item -LiteralPath $s;if($i.Length -gt 2MB -or $i.Length -ne $r.bytes -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or ('sha256:'+(Get-FileHash -LiteralPath $s).Hash.ToLowerInvariant()) -cne $r.sha256){throw 'Canonical Count1 raw drift'};[IO.Directory]::CreateDirectory((Split-Path -Parent $d))|Out-Null;Copy-Item -LiteralPath $s -Destination $d;if(-not $staleFirst){$staleFirst=$d}}
[IO.File]::AppendAllText($staleFirst,' ',[Text.UTF8Encoding]::new($false))
$cfg=[ordered]@{
 coordinatorPath=(Join-Path $stage 'resume-issued-coordinator-fresh-r11-v11.ps1');coordinatorSha256='cb819c3bf116e8651718c5a8850542f6a6b0890e7da75ba8bbce835a23ff7089'
 compileReceiptHash='1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf';exeHash='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a';serializerControlSha256='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
 issuedMetadataPath=(Join-Path $control 'issued-metadata.json');issuedMetadataHash='7d1747fd3fbd62ddb3f6adfc4e3b9519636ee64b0ae6c759a53b103e176b03cb'
 guardControlsPath=(Join-Path $ns 'controls-full-r2\metadata-controls.json');guardControlsHash='b9b55c9e5c1cba7d35bb217a88bd01b279e94d6188334ba643014af05db5a525'
 freshGuardControlsPath=(Join-Path $control 'fresh-guard.json');freshGuardControlsHash='77a7bc1ed917c176042b7aaa0afdb94c6dc67fb915cb2e03e54dd4c56aeab402'
 macSchemaReceiptPath=(Join-Path $schema 'mac-schema-receipt.json');macSchemaReceiptHash='20b11b0841f7ca730635f0dc4cfd3e31a02633ea9947f2f78ab2682e6ece47d1'
 producerRoot=$producer;controlRoot=$control;runRoot=(Join-Path $ns 'replays\r1');outputRoot=(Join-Path $ns 'replays')
 integrationGuardPath=(Join-Path $stage 'integration-fresh-r11-v6.ps1');integrationGuardHash='da5c99adc1919faf5a78cd4159b225e3ec7b38e30e92b099f6b724969445a1d7';schemaPath=(Join-Path $schema 'common.schema.json')
 admissionRoot=$repo;wrongAdmissionRoot=$producer;missingAdmissionRoot=(Join-Path $headless 'does-not-exist');staleAdmissionRoot=$stale
}
$cfgPath=Join-Path $headless 'config.json';[IO.File]::WriteAllText($cfgPath,($cfg|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$result=& (Join-Path $stage 'test-first-proof-admission-v11.ps1') -ConfigPath $cfgPath
$out=Join-Path $headless 'admission-controls.json';[IO.File]::WriteAllText($out,($result -join [Environment]::NewLine),[Text.UTF8Encoding]::new($false));$r=Read-BoundedJson $out
if($r.status -cne 'passed-source-only' -or @($r.controls).Count -ne 4 -or @($r.controls|Where-Object{$_.accepted}).Count -ne 1 -or -not $r.controls[0].accepted){throw 'Actual admission controls rejected'}
[ordered]@{kind='root-factory-admission-v11-stage-v1';status='passed-source-only';parsed=$parsed;controls=$r;controlReceiptSha256=(Get-FileHash -LiteralPath $out).Hash.ToLowerInvariant();nativeWindowActions=0;compilerActions=0;guiActions=0;lockActions=0;at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 12
