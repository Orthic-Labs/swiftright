param([Parameter(Mandatory=$true)][string]$HostRoot,[Parameter(Mandatory=$true)][string]$Plan,[Parameter(Mandatory=$true)][string]$PlanHash,[Parameter(Mandatory=$true)][string]$Prefix)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if($PlanHash -notmatch '^[a-f0-9]{64}$' -or (Get-FileHash -LiteralPath $Plan).Hash.ToLowerInvariant() -ne $PlanHash){throw 'Batch plan drift'}
$p=Get-Content -LiteralPath $Plan -Raw|ConvertFrom-Json
if($p.replays -ne 20 -or $p.qualifiedBatch -ne $false -or $p.nativeParity -ne 'hold' -or $p.noRetries -ne $true){throw 'Batch scope drift'}
if($Prefix -notmatch '^disabled-repeatability-[a-z0-9-]+$'){throw 'Unsafe fresh batch prefix'}
if($HostRoot -ne 'D:\Claude\swiftright\factory\native\windows\first-capture-corrections-v1'){throw 'Unexpected reviewed host root'}
for($i=1;$i -le 20;$i++){
 $run=Join-Path $HostRoot ($Prefix+'-'+$i.ToString('D2'))
 if(Test-Path -LiteralPath $run){throw 'Batch output already exists; no replay retry'}
}
for($i=1;$i -le 20;$i++){
 foreach($pin in $p.scriptPins.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $HostRoot $pin.Name)).Hash.ToLowerInvariant() -ne $pin.Value){throw 'Reviewed script drift'}}
 $hostPlanPath=Join-Path $HostRoot 'package\plan.json'
 if((Get-FileHash -LiteralPath $hostPlanPath).Hash.ToLowerInvariant() -ne $p.hostPlanHash){throw 'Reviewed host plan drift'}
 $hp=Get-Content -LiteralPath $hostPlanPath -Raw|ConvertFrom-Json
 $package=Join-Path $HostRoot 'package'
 $expected=@($hp.sourceBindings|ForEach-Object{$_.path})
 $actual=@('Package.swift')+@(Get-ChildItem -LiteralPath (Join-Path $package 'Sources') -Recurse -File|ForEach-Object{$_.FullName.Substring($package.Length+1).Replace('\','/')})
 if($actual.Count -ne $expected.Count -or @(Compare-Object ($actual|Sort-Object) ($expected|Sort-Object)).Count -ne 0){throw 'Host source membership drift'}
 foreach($binding in $hp.sourceBindings){if((Get-FileHash -LiteralPath (Join-Path $package $binding.path)).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Host source bytes drift'}}
 $run=Join-Path $HostRoot ($Prefix+'-'+$i.ToString('D2'))
 & (Join-Path $HostRoot 'run-corrected.ps1') -Package (Join-Path $HostRoot 'package') -RunRoot $run -CompileReceiptHash $p.compileReceiptHash -ExeHash $p.exeHash
 $d=Get-Content -LiteralPath (Join-Path $run 'dispatch.json') -Raw|ConvertFrom-Json
 if($d.status -ne 'captured-single-observational-uia-printwindow' -or -not $d.lockReleased){throw ('Batch aborted at observation '+$i)}
}
