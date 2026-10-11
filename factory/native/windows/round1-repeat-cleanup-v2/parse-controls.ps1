param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path $Output){throw 'Fresh parse output required'}
$rows=@()
foreach($name in @('capture-repeat.ps1','run-repeat.ps1','repeat-task.ps1','run-batch.ps1','namespace.ps1','test-namespace.ps1','cleanup.ps1','test-cleanup.ps1')){
 $path=Join-Path $PSScriptRoot $name;$tokens=$null;$errors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 $rows+=[ordered]@{path=$path;sha256=(Get-FileHash $path).Hash.ToLowerInvariant();errors=@($errors|ForEach-Object{[string]$_})}
}
$rows|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $Output
if(@($rows|Where-Object{$_.errors.Count}).Count){throw 'AST errors'}
