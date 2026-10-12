$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\sr0-display-selfjob-v4\v5-root-r3'
$rows=@()
foreach($f in Get-ChildItem -LiteralPath $root -File -Filter '*.ps1'){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
 foreach($e in $errors){$rows+=@{file=$f.Name;errorId=$e.ErrorId;message=$e.Message;line=$e.Extent.StartLineNumber;column=$e.Extent.StartColumnNumber;offset=$e.Extent.StartOffset;endOffset=$e.Extent.EndOffset;text=$e.Extent.Text}}
}
@{kind='factory-powershell-parser-diagnostic-v1';errors=$rows;nativeActions=0}|ConvertTo-Json -Depth 8
