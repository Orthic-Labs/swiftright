$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$ns=Join-Path $repo '.factory-work\windows-replay-r11\r14';$stage=Join-Path $ns 'overlay-memory-v15'
function Read-BoundedJson([string]$path){$i=Get-Item -LiteralPath $path;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'JSON input bound'};[IO.File]::ReadAllText($path)|ConvertFrom-Json}
$manifest=Join-Path $stage 'stage-manifest.json'
if((Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant() -cne '634bb4d5ea5459457cf573d7381bc942ac6ac5c66e17e875ed4c99222821e4a6'){throw 'Admitted source manifest drift'}
$m=Read-BoundedJson $manifest;if(@($m.files).Count -ne 13){throw 'Exact admitted source count'}
foreach($r in $m.files){$f=Join-Path $stage $r.path;$i=Get-Item -LiteralPath $f;if($i.Length -ne $r.bytes -or $i.Length -gt 1MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Admitted source drift'}}
$memory=Join-Path $ns 'memory-controls-v15-r1.json'
if((Get-FileHash -LiteralPath $memory).Hash.ToLowerInvariant() -cne '53aaae03bda130b7160a7f3a6dff560d86d742f5536e5ab9809f70a3b4be3ed3'){throw 'Actual memory controls drift'}
$mc=Read-BoundedJson $memory
if($mc.jobMemoryLimitBytes -ne 1073741824 -or $mc.jobMemoryLimitFlag -ne 512 -or @($mc.controls).Count -ne 4 -or -not $mc.childProof.originalHandleRetained -or -not $mc.childProof.terminal){throw 'Actual inherited child controls absent'}
$c=Read-BoundedJson (Join-Path $ns 'admission-controls-v14-r1\config.json')
$params=@{}
foreach($key in @('CompileReceiptHash','ExeHash','SerializerControlSha256','IssuedMetadataPath','IssuedMetadataHash','GuardControlsPath','GuardControlsHash','MacSchemaReceiptPath','MacSchemaReceiptHash','ProducerRoot','AdmissionRoot','ControlRoot','RunRoot','OutputRoot','FreshGuardControlsPath','FreshGuardControlsHash','IntegrationGuardPath','IntegrationGuardHash','SchemaPath')){$params[$key]=$c.$key}
if($params.IssuedMetadataHash -cne 'd8ac2784cce18a01e2f937503022aaa42414744e48a389abc9b507bd7d5a8b7c'){throw 'Fresh issuance drift'}
& (Join-Path $stage 'resume-issued-coordinator-fresh-r11-v12.ps1') @params -Count 20
$co=Read-BoundedJson (Join-Path $c.controlRoot 'coordinator.json');$task=Read-BoundedJson (Join-Path $c.controlRoot 'task-result.json')
if($co.status -cne 'completed-source-bound-observation' -or $co.count -ne 20 -or -not $co.lockReleased -or -not $co.wholeBatchExitConfirmed){throw 'Whole batch native release rejected'}
$mr=$task.memoryReceipt
if($mr.status -cne 'passed' -or $mr.jobMemoryLimitBytes -ne 1073741824 -or $mr.limitFlags -ne 512 -or $mr.activeProcessCount -ne 1 -or $mr.peakJobMemoryUsedBytes -gt 1073741824 -or $mr.issuedMetadataHash -cne $params.IssuedMetadataHash -or $mr.runID -cne '4c135fd2a703495ba50191ebdc5005ae'){throw 'Native batch memory proof rejected'}
[ordered]@{kind='root-factory-fresh-native-memory-v15-v1';status='completed-source-bound-observation';count=20;runID=$mr.runID;memory=$mr;coordinatorSha256=(Get-FileHash -LiteralPath (Join-Path $c.controlRoot 'coordinator.json')).Hash.ToLowerInvariant();taskSha256=(Get-FileHash -LiteralPath (Join-Path $c.controlRoot 'task-result.json')).Hash.ToLowerInvariant();lockReleased=$co.lockReleased;wholeBatchExitConfirmed=$co.wholeBatchExitConfirmed;qualification='hold';frozenTupleBound=$false}|ConvertTo-Json -Depth 8
