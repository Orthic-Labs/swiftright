$ErrorActionPreference='Stop';$p='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\collector-parse-r6.ps1'
if((Get-FileHash $p).Hash.ToLowerInvariant() -cne '1fda28696a487a15481d63ec6bbdd12f43bb5ec7ec6826e895969182c09e5cd7'){throw 'collector candidate pin'}
$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e)
$rows=@($e|ForEach-Object{@{line=$_.Extent.StartLineNumber;column=$_.Extent.StartColumnNumber;offset=$_.Extent.StartOffset;text=$_.Extent.Text;errorId=$_.ErrorId;message=$_.Message}})
@{kind='factory-candidate-powershell-parse-v1';sourceSha256='1fda28696a487a15481d63ec6bbdd12f43bb5ec7ec6826e895969182c09e5cd7';errors=$rows;nativeActions=0}|ConvertTo-Json -Depth 6
if($e.Count){exit 2}
