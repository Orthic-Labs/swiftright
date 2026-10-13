param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh controls root required'}
$contract=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'worker-contract.json')|ConvertFrom-Json
$actual=@(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -Recurse|ForEach-Object{$_.FullName.Substring($PSScriptRoot.Length+1).Replace('\','/')}|Sort-Object)
if(($actual -join "`n") -cne (@($contract.powershellMembership|Sort-Object) -join "`n")){throw 'PowerShell source membership drift'}
foreach($path in $actual){$tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $path),[ref]$tokens,[ref]$errors);if(@($errors).Count){throw ('AST failure: '+$path+': '+[string]$errors)}}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
& (Join-Path $PSScriptRoot 'test-pure.ps1') -OutputRoot (Join-Path $OutputRoot 'pure')
& (Join-Path $PSScriptRoot 'test-final-release.ps1') -OutputRoot (Join-Path $OutputRoot 'final-release')
