$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$ns=Join-Path $repo 'factory\native\windows\.work\windows-replay-r11\r17';$stage=Join-Path $ns 'overlay'
function Read-BoundedJson([string]$path){$i=Get-Item -LiteralPath $path;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'JSON input bound'};[IO.File]::ReadAllText($path)|ConvertFrom-Json}
$manifest=Join-Path $stage 'stage-manifest.json'
if((Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant() -cne '9adc91782d7fc75764d63b88fd96a3a3f42f877c48d2100e9bcef595304b555a'){throw 'Admitted source manifest drift'}
$m=Read-BoundedJson $manifest;if(@($m.files).Count -ne 15){throw 'Exact admitted source count'}
foreach($r in $m.files){$f=Join-Path $stage $r.path;$i=Get-Item -LiteralPath $f;if($i.Length -ne $r.bytes -or $i.Length -gt 1MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Admitted source drift'}}
$memory=Join-Path $ns 'memory-controls-v17-r1.json'
if((Get-FileHash -LiteralPath $memory).Hash.ToLowerInvariant() -cne 'abb27ecccd168c67003434d8c60c653da6bbb3b8fc18113dfc3334f4c1285325'){throw 'Actual memory controls drift'}
$mc=Read-BoundedJson $memory
if($mc.jobMemoryLimitBytes -ne 1073741824 -or $mc.jobMemoryLimitFlag -ne 512 -or @($mc.controls).Count -ne 4 -or -not $mc.childProof.originalHandleRetained -or -not $mc.childProof.terminal){throw 'Actual inherited child controls absent'}
$wc=Read-BoundedJson (Join-Path $ns 'worker-output-controls-r1\controls.json');if($wc.status -cne 'passed-source-only' -or @($wc.controls).Count -ne 3 -or $wc.controls[0].rejected -or -not $wc.controls[1].rejected -or -not $wc.controls[2].rejected){throw 'Actual worker namespace controls rejected'}
$c=Read-BoundedJson (Join-Path $ns 'admission-controls-v17-r1\config.json')
$params=@{}
foreach($key in @('CompileReceiptHash','ExeHash','SerializerControlSha256','IssuedMetadataPath','IssuedMetadataHash','GuardControlsPath','GuardControlsHash','MacSchemaReceiptPath','MacSchemaReceiptHash','ProducerRoot','AdmissionRoot','ControlRoot','RunRoot','OutputRoot','FreshGuardControlsPath','FreshGuardControlsHash','IntegrationGuardPath','IntegrationGuardHash','SchemaPath')){$params[$key]=$c.$key}
if($params.IssuedMetadataHash -cne '876611d051d5f9af06e87d52c148da7df5fd37381caebf4e2c2caea4935e4adf'){throw 'Fresh issuance drift'}
& (Join-Path $stage 'resume-issued-coordinator-fresh-r11-v17.ps1') @params -Count 20
$co=Read-BoundedJson (Join-Path $c.controlRoot 'coordinator.json');$task=Read-BoundedJson (Join-Path $c.controlRoot 'task-result.json')
if($co.status -cne 'completed-source-bound-observation' -or $co.count -ne 20 -or -not $co.lockReleased -or -not $co.wholeBatchExitConfirmed){throw 'Whole batch native release rejected'}
$mr=$task.memoryReceipt
if($mr.status -cne 'passed' -or $mr.jobMemoryLimitBytes -ne 1073741824 -or $mr.limitFlags -ne 512 -or $mr.activeProcessCount -ne 1 -or $mr.peakJobMemoryUsedBytes -gt 1073741824 -or $mr.issuedMetadataHash -cne $params.IssuedMetadataHash -or $mr.runID -cne '4895b9f9f6f24e79bac1b964d3182ec8'){throw 'Native batch memory proof rejected'}
[ordered]@{kind='root-factory-fresh-native-memory-v17-v1';status='completed-source-bound-observation';count=20;runID=$mr.runID;memory=$mr;coordinatorSha256=(Get-FileHash -LiteralPath (Join-Path $c.controlRoot 'coordinator.json')).Hash.ToLowerInvariant();taskSha256=(Get-FileHash -LiteralPath (Join-Path $c.controlRoot 'task-result.json')).Hash.ToLowerInvariant();lockReleased=$co.lockReleased;wholeBatchExitConfirmed=$co.wholeBatchExitConfirmed;qualification='hold';frozenTupleBound=$false}|ConvertTo-Json -Depth 8
