param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh controls output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
& (Join-Path $PSScriptRoot 'test-source-controls.ps1') -OutputPath (Join-Path $OutputRoot 'source-controls.json')
& (Join-Path $PSScriptRoot 'test-integration.ps1') -OutputRoot (Join-Path $OutputRoot 'integration')
& (Join-Path $PSScriptRoot 'test-final-exit-certificate.ps1') | Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'final-exit-controls.json')
