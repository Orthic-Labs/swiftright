param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
$contract=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'worker-contract.json')|ConvertFrom-Json
$actual=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -Recurse|ForEach-Object{$_.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/')}|Sort-Object)
$expected=@($contract.powershellMembership|Sort-Object)
if(($actual -join "`n") -cne ($expected -join "`n")){throw 'PowerShell source membership drift'}
foreach($path in $actual){$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $path),[ref]$tokens,[ref]$errors);if(@($errors).Count){throw ('AST failure: '+$path+': '+[string]$errors)}}
& (Join-Path $PSScriptRoot 'test-pure.ps1') -OutputRoot $OutputRoot
