$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r3'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne 'e44169ba5682350fa9029efef2c99cc4b34cdbbd2b866382ca695422568ef3cb'){throw 'observer source pin'}
if((Get-FileHash (Join-Path $root 'test-observer-source-controls-r2.ps1')).Hash.ToLowerInvariant() -cne '7168c09427ce18506e3fd83f71f516ea49059f4c5a9b35249dc6eefc7b0ca2d6'){throw 'observer source pin'}
foreach($name in @('observer-source-r2.ps1','test-observer-source-controls-r2.ps1')){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}}
& (Join-Path $root 'test-observer-source-controls-r2.ps1') -SourcePath (Join-Path $root 'observer-source-r2.ps1') -OutputPath (Join-Path $root 'source-controls.json')
exit 0
