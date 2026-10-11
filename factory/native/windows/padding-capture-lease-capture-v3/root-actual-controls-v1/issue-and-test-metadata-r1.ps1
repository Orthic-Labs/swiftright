$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$staged=Join-Path $repo '.factory-work\metadata-controls';$zip=Join-Path $repo '.factory-work\metadata-controls.zip'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'cd9b9216bb1f7891c8d2bff5ac06ab205951debbe43492f090c1bac747ccaa27'){throw 'Metadata transport zip drift'}
if(Test-Path -LiteralPath $staged){throw 'Fresh metadata extraction required'}
Expand-Archive -LiteralPath $zip -DestinationPath $staged
$manifest=Join-Path $staged 'transfer-manifest.json'
if((Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant() -cne 'e9f786f89456de4ae19b07af70ca4825624c8f2bc356e6edeea33bc106205a79'){throw 'Metadata transport manifest drift'}
$doc=[IO.File]::ReadAllText($manifest)|ConvertFrom-Json
$pkg=Join-Path $repo 'factory\native\windows\padding-capture-lease-capture-v3'
if((Get-FileHash -LiteralPath (Join-Path $pkg 'support\integration.ps1')).Hash.ToLowerInvariant() -cne $doc.frozenIntegrationSha256){throw 'Frozen metadata integration source drift'}
foreach($r in $doc.files){
 if($r.path -cnotmatch '^factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/[a-z0-9.-]+$'){throw 'Unsafe metadata transport member'}
 $f=Join-Path $staged ($r.path -replace '/','\');$dest=Join-Path $repo ($r.path -replace '/','\')
 if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Metadata source bytes drift'}
 if(Test-Path -LiteralPath $dest){if((Get-Item -LiteralPath $dest).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $dest).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Existing metadata source differs'}}
 if($f.EndsWith('.ps1')){$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw 'Metadata source parse failure'}}
}
foreach($r in $doc.files){$f=Join-Path $staged ($r.path -replace '/','\');$dest=Join-Path $repo ($r.path -replace '/','\');if(-not(Test-Path -LiteralPath $dest)){[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($dest))|Out-Null;[IO.File]::Copy($f,$dest,$false)}}
$CompileHash='1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf';$ExeHash='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a';$SerializerHash='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
$coordinator=Join-Path $pkg 'coordinator-single-r1';$run=Join-Path $pkg 'actual-single-r1';$issued=Join-Path $coordinator 'issued-metadata.json'
if(Test-Path -LiteralPath $coordinator){throw 'Fresh Count1 metadata output required'}
[IO.Directory]::CreateDirectory($coordinator)|Out-Null
& (Join-Path $pkg 'issue-before-launch.ps1') -Count 1 -RunRoot $run -OutputPath $issued -CompileReceiptSha256 $CompileHash -ExeSha256 $ExeHash -SerializerControlSha256 $SerializerHash
$IssuedHash=(Get-FileHash -LiteralPath $issued).Hash.ToLowerInvariant()
$metadata=Join-Path $pkg 'root-metadata-controls-v1';$actual=Join-Path $metadata 'actual';if(Test-Path -LiteralPath $actual){throw 'Fresh metadata actual controls output required'};[IO.Directory]::CreateDirectory($actual)|Out-Null
& (Join-Path $metadata 'test-metadata-guard-controls.ps1') -IssuedMetadataPath $issued -IssuedMetadataHash $IssuedHash -RunRoot $run -Count 1 -CompileHash $CompileHash -ExeHash $ExeHash -SerializerHash $SerializerHash -ProducerRoot $pkg -ControlRoot (Join-Path $actual 'controls-r1') -OutputPath (Join-Path $actual 'metadata-controls-r1.json')
Write-Output 'ROOT_METADATA_FULL_GUARD_CONTROLS_RETURNED nativeLaunches=0'
foreach($name in @('candidate-tuple.json','candidate-binding.json','issued-metadata.json')){$p=Join-Path $coordinator $name;Write-Output ('OUTPUT_SHA256 '+$name+' '+(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant())}
