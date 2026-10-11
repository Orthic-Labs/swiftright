param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh control output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
& (Join-Path $PSScriptRoot 'parse-controls.ps1') -Output (Join-Path $OutputRoot 'parse.json')
& (Join-Path $PSScriptRoot 'test-namespace.ps1') -OutputRoot (Join-Path $OutputRoot 'namespace')
& (Join-Path $PSScriptRoot 'test-cleanup.ps1') -OutputRoot (Join-Path $OutputRoot 'cleanup')
& (Join-Path $PSScriptRoot 'test-stream-seal.ps1') -OutputRoot (Join-Path $OutputRoot 'stream-seal')
& (Join-Path $PSScriptRoot 'test-owned-close.ps1') -OutputRoot (Join-Path $OutputRoot 'owned-close')
& (Join-Path $PSScriptRoot 'test-capture-exit-proof.ps1') -OutputRoot (Join-Path $OutputRoot 'capture-exit')
& (Join-Path $PSScriptRoot 'test-process-streams.ps1') -OutputRoot (Join-Path $OutputRoot 'process-streams')
& (Join-Path $PSScriptRoot 'test-kernel-bounds.ps1') -OutputRoot (Join-Path $OutputRoot 'kernel-bounds')
& (Join-Path $PSScriptRoot 'test-mac-proof.ps1') -OutputRoot (Join-Path $OutputRoot 'parent-mac-proof')
& (Join-Path $PSScriptRoot 'test-lifecycle-proof.ps1') -OutputRoot (Join-Path $OutputRoot 'lifecycle-binding')
[ordered]@{kind='factory-stack-lifecycle-diagnostic-capture-controls-v1';status='passed';compilerInvocations=0;rendererLoaded=$false;nativeWindows=0;consoleControlsOnly=$true}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
