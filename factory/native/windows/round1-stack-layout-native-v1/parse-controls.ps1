# Pure AST inspection only: no script execution, compiler, process or desktop calls.
param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Fresh parse output required'}
$rows=@()
foreach($name in @('capture-round1.ps1','round1-task.ps1','run-round1.ps1')){
 $path=Join-Path $PSScriptRoot $name
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 $rows+= [ordered]@{path=$path;sha256=(Get-FileHash $path).Hash.ToLowerInvariant();errors=@($errors|ForEach-Object{[string]$_})}
}
[ordered]@{kind='round1-native-pure-parse';scriptExecution=$false;compiler=$false;desktop=$false;rows=$rows}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $Output
if(@($rows|Where-Object{$_.errors.Count -ne 0}).Count){throw 'AST errors'}
