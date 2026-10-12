$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r5'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne '0bf4ab3a1e0b3ebad5c97dd64ddac239031ab8650126e569c30dfe2e042c50b2'){throw 'observer source pin'}
if((Get-FileHash (Join-Path $root 'test-observer-source-controls-r2.ps1')).Hash.ToLowerInvariant() -cne 'fbe481bc427564786bb8f4279f3f18b7281541f68531b11bed6eb63753dba403'){throw 'observer source pin'}
foreach($name in @('observer-source-r2.ps1','test-observer-source-controls-r2.ps1')){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}}
& (Join-Path $root 'test-observer-source-controls-r2.ps1') -SourcePath (Join-Path $root 'observer-source-r2.ps1') -OutputPath (Join-Path $root 'source-controls.json')
exit 0
