# Actual IO/console controls required before compiler. No pass labels from caller.
function Assert-CompilerStreamControls([string]$Root){
 . (Join-Path $Root 'cleanup.ps1')
 if((Get-FileHash -LiteralPath (Join-Path $Root 'stream-control-inputs.json')).Hash.ToLowerInvariant() -cne '640ee89a374b1615fd96661f6b510835232f0a318221f8f16696d7c64c82fe5c'){throw 'Exact stream input pins required'}
 $pins=Get-Content -Raw -LiteralPath (Join-Path $Root 'stream-control-inputs.json')|ConvertFrom-Json
 foreach($prop in $pins.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $Root $prop.Name)).Hash.ToLowerInvariant() -cne $prop.Value){throw 'Stream control source drift'}}
 $receipt=Get-Content -Raw -LiteralPath (Join-Path $Root 'stream-control-results\receipt.json')|ConvertFrom-Json
 if($receipt.kind -cne 'actual-compiler-stream-controls-v2' -or $receipt.completed -isnot [bool] -or -not $receipt.completed -or $receipt.compilerInvocations -isnot [int] -or $receipt.compilerInvocations -ne 0){throw 'Actual stream controls missing'}
 $required=@('stream-control-results\console\controls.json','stream-control-results\io\controls.json')
 foreach($path in $required){if(@($receipt.files|Where-Object{$_.path -ceq $path}).Count -ne 1){throw 'Control raw binding missing'}}
 foreach($binding in $receipt.files){if((Get-FileHash -LiteralPath (Join-Path $Root $binding.path)).Hash.ToLowerInvariant() -cne $binding.sha256){throw 'Stream control raw drift'}}
 foreach($prop in $pins.PSObject.Properties){if($receipt.inputs.($prop.Name) -cne $prop.Value){throw 'Stream control invocation source drift'}}
 $rows=@(Get-Content -Raw -LiteralPath (Join-Path $Root 'stream-control-results\console\controls.json')|ConvertFrom-Json)
 if($rows.Count -ne 2 -or @($rows.mode|Select-Object -Unique).Count -ne 2 -or @($rows|Where-Object{$_.mode -cnotin @('volume','inherit')}).Count){throw 'Stream modes incomplete'}
 foreach($row in $rows){
  if($row.primaryError -or -not (Test-FactoryKernelExitCertificate $row.cleanup)){throw 'Stream child exit control failed'}
  if($row.mode -ceq 'volume' -and @($row.rawStreams|Where-Object{$_.sealed -isnot [bool] -or -not $_.sealed -or $_.destinationClosed -isnot [bool] -or -not $_.destinationClosed -or $_.taskStatus -cne 'RanToCompletion' -or $_.closureTaskStatus -cne 'RanToCompletion'}).Count){throw 'Volume streams unsealed'}
  if($row.mode -ceq 'inherit' -and (-not $row.initial.failureDisposition.stableAfterSourceSettlement -or -not (Test-FactoryKernelExitCertificate $row.holderCleanup))){throw 'Inherited writer control failed'}
 }
 $io=@(Get-Content -Raw -LiteralPath (Join-Path $Root 'stream-control-results\io\controls.json')|ConvertFrom-Json)
 if($io.Count -lt 4){throw 'IO closure controls absent'}
}
