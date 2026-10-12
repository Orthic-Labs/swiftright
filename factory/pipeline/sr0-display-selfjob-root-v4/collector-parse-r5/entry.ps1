$ErrorActionPreference='Stop';$p='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\collector-parse-r5.ps1'
if((Get-FileHash $p).Hash.ToLowerInvariant() -cne '8445b49736fad71ef946749be4c16edfd29b4c1ff7966d63e3d61291fd63d024'){throw 'collector candidate pin'}
$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
$rows=@($e|ForEach-Object{@{line=$_.Extent.StartLineNumber;column=$_.Extent.StartColumnNumber;offset=$_.Extent.StartOffset;text=$_.Extent.Text;errorId=$_.ErrorId;message=$_.Message}})
@{kind='factory-candidate-powershell-parse-v1';sourceSha256='8445b49736fad71ef946749be4c16edfd29b4c1ff7966d63e3d61291fd63d024';errors=$rows;nativeActions=0}|ConvertTo-Json -Depth 6
if($e.Count){exit 2}
