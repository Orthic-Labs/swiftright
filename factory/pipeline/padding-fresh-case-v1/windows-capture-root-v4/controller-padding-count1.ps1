# Source-only Count1 admission; root invokes reviewed native producer only after this gate.
param([Parameter(Mandatory=$true)][string]$Config,[switch]$PreflightOnly)
$ErrorActionPreference='Stop'
function R([string]$p,[long]$lim=67108864){$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or $i.LinkType -or $i.Length -gt $lim){throw 'bounded regular file required'};return $i}
function H([string]$p,[long]$lim=67108864){R $p $lim|Out-Null;(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant()}
function J([string]$p){R $p 2097152|Out-Null;Get-Content -Raw -LiteralPath $p|ConvertFrom-Json}
$c=J $Config;if($c.kind -ne 'factory-padding-count1-config-v1'){throw 'Padding Count1 config kind mismatch'}
$root=[IO.Path]::GetFullPath([string]$c.controlRoot);if([IO.Path]::GetFullPath($Config) -cne (Join-Path $root 'count1-config.json')){throw 'Count1 config path drift'}
$src=[IO.Path]::GetFullPath([string]$c.sourceInputsPath);$sh=[string]$c.sourceInputsHash;if($sh -notmatch '^[0-9a-f]{64}$' -or (H $src 2097152) -cne $sh){throw 'source inputs drift'}
$d=J $src;if($d.kind -notin @('factory-padding-source-inputs-v2','factory-padding-source-inputs-v3') -or [int]$d.count -ne 1){throw 'fresh Padding Count1 source inputs required'}
foreach($f in @('caseID','caseHash','sourceHash','tupleID','planHash','compileReceiptHash','exeHash','runtimeSourceCommit','rendererPath','rendererSha256','serializerControlSha256')){if([string]::IsNullOrWhiteSpace([string]$d.$f)){throw "source field missing: $f"}}
foreach($x in @(@{p=$c.planPath;h=$c.planHash;n='plan'},@{p=$c.compileReceiptPath;h=$c.compileReceiptHash;n='compile receipt'},@{p=$c.exePath;h=$c.exeHash;n='executable'},@{p=$c.rendererPath;h=$c.rendererSha256;n='renderer'},@{p=$c.serializerPath;h=$c.serializerControlSha256;n='serializer'})){if([string]$x.h -notmatch '^[0-9a-f]{64}$' -or (H ([IO.Path]::GetFullPath([string]$x.p))) -cne [string]$x.h){throw "$($x.n) drift"}}
$plan=J $c.planPath;$rec=J $c.compileReceiptPath
if($plan.case.id -cne $d.caseID -or $plan.case.hash -cne $d.caseHash -or $plan.sourceHash -cne $d.sourceHash -or $rec.exitCode -ne 0 -or $rec.kernelWait -ne 0 -or $rec.originalHandleRetained -ne $true -or $rec.streamsSealed -ne $true -or $rec.jobActiveCount -ne 0){throw 'compile/source closure mismatch'}
if([IO.Path]::GetFullPath([string]$c.runRoot) -notlike (([IO.Path]::GetFullPath([string]$c.outputRoot))+'*')){throw 'run root outside fresh output'}
if(Test-Path -LiteralPath $c.runRoot){throw 'fresh Count1 run root required'}
$out=[ordered]@{kind='factory-padding-count1-admission-v1';status='passed-source-only';count=1;sourceInputsHash=$sh;caseID=$d.caseID;caseHash=$d.caseHash;tupleID=$d.tupleID;planHash=$c.planHash;compileReceiptHash=$c.compileReceiptHash;exeHash=$c.exeHash;rendererSha256=$c.rendererSha256;memoryLimitBytes=1073741824;limitFlags=512;killOnJobClose=$false;nativeWindowActions=0;compilerActions=0;lockActions=0}
New-Item -ItemType Directory -Path $root -Force|Out-Null;$out|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $root 'count1-admission.json') -Encoding UTF8
$out|ConvertTo-Json -Depth 10
