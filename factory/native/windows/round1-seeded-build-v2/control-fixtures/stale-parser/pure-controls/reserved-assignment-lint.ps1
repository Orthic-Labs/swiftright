param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Fresh lint output required'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$rows=@()
$assignmentPattern='(?im)\$(?:Host|PID|input)\b\s*(?:=(?!=)|\+=|-=|\+\+|--)'
$loopPattern='(?im)foreach\s*\(\s*\$(?:Host|PID|input)\b\s+in\b'
foreach($file in @(Get-ChildItem -LiteralPath $root -Recurse -File -Filter '*.ps1'|Where-Object{$_.FullName -notmatch '\\control-results\\|\\control-fixtures\\'})){
 $text=[IO.File]::ReadAllText($file.FullName)
 $matches=@([regex]::Matches($text,$assignmentPattern))+@([regex]::Matches($text,$loopPattern))
 $rows+=@{path=$file.FullName;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant();reservedAssignments=@($matches|ForEach-Object{$_.Value})}
}
$bad=@($rows|Where-Object{$_.reservedAssignments.Count -ne 0})
@{kind='reserved-automatic-assignment-lint-v3';variables=@('Host','PID','input');files=$rows;pass=($bad.Count -eq 0);compilerInvocations=0}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath $Output
if($bad.Count -ne 0){throw 'Reserved automatic variable assignment'}
