# Root-reviewed hidden console controls only; no Swift compiler/renderer/window/lock calls.
$ErrorActionPreference='Stop'
$out=Join-Path $PSScriptRoot 'stream-control-results'
if(Test-Path -LiteralPath $out){throw 'Fresh stream control output required'}
New-Item -ItemType Directory -Path $out|Out-Null
$started=[DateTimeOffset]::UtcNow.ToString('o')
$inputs=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'stream-control-inputs.json')|ConvertFrom-Json
foreach($prop in $inputs.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $prop.Name)).Hash.ToLowerInvariant() -cne $prop.Value){throw 'Stream control source drift'}}
& (Join-Path $PSScriptRoot 'test-stream-seal.ps1') -OutputRoot (Join-Path $out 'io')
& (Join-Path $PSScriptRoot 'test-process-streams-bounded.ps1') -OutputRoot (Join-Path $out 'console')
$receipt=[ordered]@{kind='actual-compiler-stream-controls-v2';completed=$true;startedAt=$started;finishedAt=[DateTimeOffset]::UtcNow.ToString('o');coordinatorPid=$PID;inputs=$inputs;compilerInvocations=0;nativeWindows=0;files=@()}
$receipt.files=@(Get-ChildItem -LiteralPath $out -Recurse -File|ForEach-Object{@{path=$_.FullName.Substring($PSScriptRoot.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant()}})
$receipt|ConvertTo-Json -Depth 14|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'receipt.json')
. (Join-Path $PSScriptRoot 'stream-control-admission.ps1')
Assert-CompilerStreamControls $PSScriptRoot
