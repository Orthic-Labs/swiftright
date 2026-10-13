$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$ns=Join-Path $repo '.factory-work\windows-replay-r11\r16';$stage=Join-Path $ns 'overlay'
function Read-BoundedJson([string]$path){$i=Get-Item -LiteralPath $path;if($i.Length -gt 2MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'JSON input bound'};[IO.File]::ReadAllText($path)|ConvertFrom-Json}
$manifest=Join-Path $stage 'stage-manifest.json'
if((Get-FileHash -LiteralPath $manifest).Hash.ToLowerInvariant() -cne '8c86772efb2132cae287156a04180c47136ffeb15a187b83b9decb0934c6df42'){throw 'Admitted source manifest drift'}
$m=Read-BoundedJson $manifest;if(@($m.files).Count -ne 13){throw 'Exact admitted source count'}
foreach($r in $m.files){$f=Join-Path $stage $r.path;$i=Get-Item -LiteralPath $f;if($i.Length -ne $r.bytes -or $i.Length -gt 1MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Admitted source drift'}}
$memory=Join-Path $ns 'memory-controls-v16-r1.json'
if((Get-FileHash -LiteralPath $memory).Hash.ToLowerInvariant() -cne '6bf3d87bb52fd0aae77c3737494bb50fd63b8ed9e21d083dbd8e4cb3dda72d1c'){throw 'Actual memory controls drift'}
$mc=Read-BoundedJson $memory
if($mc.jobMemoryLimitBytes -ne 1073741824 -or $mc.jobMemoryLimitFlag -ne 512 -or @($mc.controls).Count -ne 4 -or -not $mc.childProof.originalHandleRetained -or -not $mc.childProof.terminal){throw 'Actual inherited child controls absent'}
$c=Read-BoundedJson (Join-Path $ns 'admission-controls-v16-r2\config.json')
$params=@{}
foreach($key in @('CompileReceiptHash','ExeHash','SerializerControlSha256','IssuedMetadataPath','IssuedMetadataHash','GuardControlsPath','GuardControlsHash','MacSchemaReceiptPath','MacSchemaReceiptHash','ProducerRoot','AdmissionRoot','ControlRoot','RunRoot','OutputRoot','FreshGuardControlsPath','FreshGuardControlsHash','IntegrationGuardPath','IntegrationGuardHash','SchemaPath')){$params[$key]=$c.$key}
if($params.IssuedMetadataHash -cne '7216cd29266556cff4fec9a214f4bd5b403218db27d2007edc90823334e500e6'){throw 'Fresh issuance drift'}
& (Join-Path $stage 'resume-issued-coordinator-fresh-r11-v16.ps1') @params -Count 20
$co=Read-BoundedJson (Join-Path $c.controlRoot 'coordinator.json');$task=Read-BoundedJson (Join-Path $c.controlRoot 'task-result.json')
if($co.status -cne 'completed-source-bound-observation' -or $co.count -ne 20 -or -not $co.lockReleased -or -not $co.wholeBatchExitConfirmed){throw 'Whole batch native release rejected'}
$mr=$task.memoryReceipt
if($mr.status -cne 'passed' -or $mr.jobMemoryLimitBytes -ne 1073741824 -or $mr.limitFlags -ne 512 -or $mr.activeProcessCount -ne 1 -or $mr.peakJobMemoryUsedBytes -gt 1073741824 -or $mr.issuedMetadataHash -cne $params.IssuedMetadataHash -or $mr.runID -cne '01acb1d24a04471fa5709dac1c4a73c5'){throw 'Native batch memory proof rejected'}
[ordered]@{kind='root-factory-fresh-native-memory-v16-v1';status='completed-source-bound-observation';count=20;runID=$mr.runID;memory=$mr;coordinatorSha256=(Get-FileHash -LiteralPath (Join-Path $c.controlRoot 'coordinator.json')).Hash.ToLowerInvariant();taskSha256=(Get-FileHash -LiteralPath (Join-Path $c.controlRoot 'task-result.json')).Hash.ToLowerInvariant();lockReleased=$co.lockReleased;wholeBatchExitConfirmed=$co.wholeBatchExitConfirmed;qualification='hold';frozenTupleBound=$false}|ConvertTo-Json -Depth 8
