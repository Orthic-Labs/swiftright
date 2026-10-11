$ErrorActionPreference='Stop'
if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'root-before-compile-controls.ps1')).Hash.ToLowerInvariant() -cne '824e698483125e67ca4e1e420c490c0c901b96c4860ca039cf242beb1867adc1'){throw 'Precompile admission drift'}
if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'root-before-compile-controls-r1\receipt.json')).Hash.ToLowerInvariant() -cne 'cf176732cfabdbfbbda6ba9e3ca00ef66773051231e54a279326fa7e79424f9a'){throw 'Precompile admission drift'}
if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'run-compile.ps1')).Hash.ToLowerInvariant() -cne '6447237fd4819d498fb562aa722ce351a272cd1fc0af726be63744e4125c599a'){throw 'Precompile admission drift'}
$actual=Get-Content -Raw (Join-Path $PSScriptRoot 'root-before-compile-controls-r1\receipt.json')|ConvertFrom-Json
if($actual.passed -ne $true -or $actual.compilerInvocations -ne 0 -or $actual.nativeCalls -ne 0){throw 'Precompile control failure'}
& (Join-Path $PSScriptRoot 'run-compile.ps1')
