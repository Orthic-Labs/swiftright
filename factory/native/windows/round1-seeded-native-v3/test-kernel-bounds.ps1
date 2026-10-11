param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh control namespace required'}
New-Item -ItemType Directory $OutputRoot|Out-Null
& (Join-Path $PSScriptRoot 'test-cleanup.ps1') -OutputRoot (Join-Path $OutputRoot 'fake-kernel')
& (Join-Path $PSScriptRoot 'test-capture-exit-proof.ps1') -OutputRoot (Join-Path $OutputRoot 'proof-gates')
& (Join-Path $PSScriptRoot 'test-process-streams-bounded.ps1') -OutputRoot (Join-Path $OutputRoot 'actual-streams')
[ordered]@{kind='kernel-exit-and-raw-stream-bounded-controls-v3';status='passed';consoleOnly=$true;rendererLoaded=$false;exitMilliseconds=15000;streamMilliseconds=5000;controls=@('fake-kernel/controls.json','proof-gates/controls.json','actual-streams/controls.json')}|ConvertTo-Json|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
