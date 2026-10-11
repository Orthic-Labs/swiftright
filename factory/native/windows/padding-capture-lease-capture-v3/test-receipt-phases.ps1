param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh receipt controls output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
. (Join-Path $PSScriptRoot 'support\stream-seal.ps1')
$source=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'capture-repeat.ps1')
$phases=@([regex]::Matches($source,'Write-FactoryDiagnosticJson \(Join-Path \$dir ''([^'']*ordering[^'']*)''\) \$ordering')|ForEach-Object{$_.Groups[1].Value})
$expected=@('capture-ordering-worker-ready.json','capture-ordering-pixels-start.json','capture-ordering-pixels-complete.json','capture-ordering-close-pending.json','capture-ordering.json')
if($phases.Count -ne 5 -or ($phases -join '|') -cne ($expected -join '|')){throw 'Exact production immutable ordering phases required'}
$rows=@()
foreach($attempted in @($false,$true)){
 $lane=Join-Path $OutputRoot ([string]$attempted);New-Item -ItemType Directory -Path $lane|Out-Null
 $inventory=[ordered]@{attempted=$false}
 Write-FactoryDiagnosticJson (Join-Path $lane 'declared-worker-inventory.json') $inventory
 $inventory.attempted=$attempted
 Write-FactoryDiagnosticJson (Join-Path $lane 'owned-worker-inventory.json') $inventory
 foreach($phase in $phases){Write-FactoryDiagnosticJson (Join-Path $lane $phase) ([ordered]@{phase=$phase})}
 if((Get-Content -Raw (Join-Path $lane 'declared-worker-inventory.json')|ConvertFrom-Json).attempted -ne $false){throw 'Declaration snapshot mutated'}
 if((Get-Content -Raw (Join-Path $lane 'owned-worker-inventory.json')|ConvertFrom-Json).attempted -ne $attempted){throw 'Terminal inventory branch mismatch'}
 $before=(Get-FileHash (Join-Path $lane 'capture-ordering.json')).Hash
 $rejected=$false;try{Write-FactoryDiagnosticJson (Join-Path $lane 'capture-ordering.json') @{forged=$true}}catch{$rejected=$true}
 if(-not $rejected -or (Get-FileHash (Join-Path $lane 'capture-ordering.json')).Hash -cne $before){throw 'Immutable overwrite control failed'}
 $rows+=@{attempted=$attempted;phaseWrites=5;declarationUnchanged=$true;terminalBranchExact=$true;overwriteRejected=$true;rawUnchanged=$true}
}
Write-FactoryDiagnosticJson (Join-Path $OutputRoot 'controls.json') @{status='passed';branches=$rows;productionWriter='Write-FactoryDiagnosticJson';nativeActions=0}
