param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Fresh lint output required'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$rows=@()
$assignmentPattern='(?im)\$(?:Host|PID|input)\b\s*(?:=(?!=)|\+=|-=|\+\+|--)'
$loopPattern='(?im)foreach\s*\(\s*\$(?:Host|PID|input)\b\s+in\b'
$scope=Join-Path $root 'producer-source-scope.ps1'
if((Get-FileHash -LiteralPath $scope).Hash.ToLowerInvariant() -cne 'd0485e74d694f700b2540dab2c57f2d3deb342758b965adcb3ddbc32faa6fd9b'){throw 'Source-scope guard drift'}
. $scope
foreach($file in @(Get-FactoryProducerScripts $root)){
 $text=[IO.File]::ReadAllText($file.FullName)
 $matches=@([regex]::Matches($text,$assignmentPattern))+@([regex]::Matches($text,$loopPattern))
 $rows+=@{path=$file.FullName;sha256=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant();reservedAssignments=@($matches|ForEach-Object{$_.Value})}
}
$bad=@($rows|Where-Object{$_.reservedAssignments.Count -ne 0})
@{kind='reserved-automatic-assignment-lint-v3';variables=@('Host','PID','input');files=$rows;pass=($bad.Count -eq 0);compilerInvocations=0}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath $Output
if($bad.Count -ne 0){throw 'Reserved automatic variable assignment'}
