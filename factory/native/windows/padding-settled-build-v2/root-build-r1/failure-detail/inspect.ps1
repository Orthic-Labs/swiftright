$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
$lint=Get-Content -Raw -LiteralPath (Join-Path $root 'control-results\reserved-lint.json')|ConvertFrom-Json
$expected=@($lint.files|ForEach-Object{$_.path})
$actual=@(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1'|Where-Object{$_.FullName -notmatch '\\control-results\\|\\control-fixtures\\'}|ForEach-Object{$_.FullName})
[ordered]@{kind='lint-membership-failure-diagnosis';expectedCount=$expected.Count;actualCount=$actual.Count;extra=@($actual|Where-Object{$expected -cnotcontains $_});missing=@($expected|Where-Object{$actual -cnotcontains $_});compilerStarted=$false;nativeWindows=0}|ConvertTo-Json -Depth 8
