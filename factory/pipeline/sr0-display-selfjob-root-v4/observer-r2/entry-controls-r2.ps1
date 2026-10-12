$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r2'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne '3501179ba9f69ebd198d248117cf18e1496402415eebd8583ad369774e59f4ee'){throw 'observer source pin'}
if((Get-FileHash (Join-Path $root 'test-observer-source-controls-r2.ps1')).Hash.ToLowerInvariant() -cne '534431679c9d7541916488a9b7c31f4b6bef466aac461bb328cb8eaa5f94d39d'){throw 'observer source pin'}
foreach($name in @('observer-source-r2.ps1','test-observer-source-controls-r2.ps1')){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}}
& (Join-Path $root 'test-observer-source-controls-r2.ps1') -SourcePath (Join-Path $root 'observer-source-r2.ps1') -OutputPath (Join-Path $root 'source-controls.json')
exit 0
