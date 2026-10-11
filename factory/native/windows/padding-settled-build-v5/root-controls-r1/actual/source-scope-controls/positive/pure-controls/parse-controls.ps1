param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Fresh parse output required'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$rows=@()
foreach($rel in @('build-hosts-v2.ps1','cleanup-decision.ps1','control-admission.ps1','pure-controls\test-cleanup.ps1','pure-controls\test-host-inputs.ps1','run-controls.ps1','pure-controls\reserved-assignment-lint.ps1','pure-controls\parse-controls.ps1','pure-controls\test-integer-admission.ps1')){
 $path=[IO.Path]::GetFullPath((Join-Path $root $rel));$tokens=$null;$errors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 $rows+=@{path=$path;sha256=(Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant();errors=@($errors|ForEach-Object{[string]$_})}
}
ConvertTo-Json -InputObject @($rows) -Depth 8|Set-Content -Encoding UTF8 -LiteralPath $Output
if(@($rows|Where-Object{$_.errors.Count}).Count){throw 'AST errors'}
