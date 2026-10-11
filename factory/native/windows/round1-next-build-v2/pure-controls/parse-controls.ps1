param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Fresh parse output required'}
$rows=@()
foreach($rel in @('..\build-hosts-v2.ps1','..\cleanup-decision.ps1','test-cleanup.ps1')){
 $path=Join-Path $PSScriptRoot $rel;$tokens=$null;$errors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 $rows+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();errors=@($errors|ForEach-Object{[string]$_})}
}
$rows|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 -LiteralPath $Output
if(@($rows|Where-Object{$_.errors.Count}).Count){throw 'AST errors'}
