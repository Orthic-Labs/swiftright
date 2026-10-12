$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r4'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne '5bf73c1a2401ad13372b6bb6eac6f07e14afb7998aa9e32cf21f06059ca0a837'){throw 'observer source pin'}
if((Get-FileHash (Join-Path $root 'test-observer-source-controls-r2.ps1')).Hash.ToLowerInvariant() -cne '72f4c96dd857e0dd3072dc8ee76166236564192828f58c852af3c958226b67c6'){throw 'observer source pin'}
foreach($name in @('observer-source-r2.ps1','test-observer-source-controls-r2.ps1')){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}}
& (Join-Path $root 'test-observer-source-controls-r2.ps1') -SourcePath (Join-Path $root 'observer-source-r2.ps1') -OutputPath (Join-Path $root 'source-controls.json')
exit 0
