$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\observer-r6'
if((Get-FileHash (Join-Path $root 'observer-source-r2.ps1')).Hash.ToLowerInvariant() -cne '986e2c306d1a05dcd92d39469d201dab280f7c29e61f3b6452fb69e439a599d1'){throw 'observer source pin'}
if((Get-FileHash (Join-Path $root 'test-observer-source-controls-r2.ps1')).Hash.ToLowerInvariant() -cne 'e8f2973ecd4bf50fcff177974346a5907d2619ae54d53d0f72cf060adde44443'){throw 'observer source pin'}
foreach($name in @('observer-source-r2.ps1','test-observer-source-controls-r2.ps1')){$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}}
& (Join-Path $root 'test-observer-source-controls-r2.ps1') -SourcePath (Join-Path $root 'observer-source-r2.ps1') -OutputPath (Join-Path $root 'source-controls.json')
exit 0
