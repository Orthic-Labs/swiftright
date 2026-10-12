param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'support\final-exit-certificate.ps1')
$results=@();$raw=[Text.Encoding]::UTF8.GetBytes('raw');$hash=Get-FactoryUiaFinalBytesHash $raw
$start=[ordered]@{pid=56152;retainedHandle=1832;path='D:\Windows\powershell.exe';startedAt='2026-10-11T10:37:40.8454176Z';lockOwner='owner';workerId='worker-root';workerExeHash=$hash;sourceContractHash=$hash;configHash=$hash;workerScriptHash=$hash}
$sample=[ordered]@{phase='raw-closure-final';waitMilliseconds=0;retainedHandle=1832;handlePid=56152;kernelBefore=0;kernelAfter=0;exitCode=1;getExitCodeSucceeded=$true;errors=@()}
$stream=[ordered]@{name='stdout';copyCompleted=$true;destinationClosed=$true;sealed=$true;taskIsCompleted=$true;taskIsFaulted=$false;taskIsCanceled=$false;taskStatus='RanToCompletion';taskException='';closureTaskStatus='RanToCompletion';hashQualification='sealed-raw';path='stdout';sha256=$hash;closure=[ordered]@{deadlineMilliseconds=5000;flushCompleted=$true;destinationClosed=$true;completedWithinDeadline=$true;deadlineExpired=$false;error=''}}
function Copy-Value($v){$v|ConvertTo-Json -Depth 20|ConvertFrom-Json}
$stderr=Copy-Value $stream;$stderr.name='stderr';$stderr.path='stderr';$streams=@($stream,$stderr)
function Check([string]$name,[bool]$ok){if(-not $ok){throw ('Control failed: '+$name)};$script:results+=@([ordered]@{name=$name;passed=$true})}
Check 'failed-worker-nonzero-final-exit-can-prove-release-only' (Test-FactoryUiaFinalExitSample $sample $start $streams)
foreach($field in @('kernelBefore','kernelAfter')){foreach($value in @(258,'0',$null)){$copy=Copy-Value $sample;$copy.$field=$value;Check ('reject-'+$field+'-'+[string]$value) (-not(Test-FactoryUiaFinalExitSample $copy $start $streams))}}
foreach($field in @('retainedHandle','handlePid')){$copy=Copy-Value $sample;$copy.$field=999;Check ('reject-original-identity-'+$field) (-not(Test-FactoryUiaFinalExitSample $copy $start $streams))}
$copy=Copy-Value $sample;$copy.exitCode=259;Check 'reject-STILL_ACTIVE' (-not(Test-FactoryUiaFinalExitSample $copy $start $streams))
$copy=Copy-Value $sample;$copy.getExitCodeSucceeded=$false;Check 'reject-exitcode-query-failure' (-not(Test-FactoryUiaFinalExitSample $copy $start $streams))
foreach($field in @('sealed','destinationClosed','taskIsCompleted')){$copy=Copy-Value $streams;$copy[0].$field=$false;Check ('reject-raw-'+$field) (-not(Test-FactoryUiaFinalExitSample $sample $start $copy))}
$cert=New-FactoryUiaFinalExitCertificate $sample $start $streams
Check 'honest-worker-identity-no-compiler-receipt' (-not($cert.start.Contains('compileReceiptHash')))
Check 'release-scope-only' ($cert.scope -ceq 'owner-release-only' -and $cert.qualification -ceq 'failed-or-successful-snapshot-only')
Check 'missing-owned-worker-holds' (-not(Test-FactoryAllUiaWorkerReleaseProofs @('worker-root') @() {param($ref) return $raw}))
Check 'duplicate-inventory-holds' (-not(Test-FactoryAllUiaWorkerReleaseProofs @('worker-root','worker-root') @() {param($ref) return $raw}))
# Full byte-backed proof: failed original result remains failed & hash-bound.
$memory=@{};$memory['exe']=$raw;$memory['script']=$raw;$memory['stdout']=$raw;$memory['stderr']=$raw
function Store-Value([string]$ref,$v){$bytes=[Text.Encoding]::UTF8.GetBytes(($v|ConvertTo-Json -Depth 20));$script:memory[$ref]=$bytes;return Get-FactoryUiaFinalBytesHash $bytes}
$contract=[ordered]@{sourceBindings=@([ordered]@{path='worker.ps1';sha256=$hash})}
$start.sourceContractHash=Store-Value 'contract' $contract
$start.configHash=Store-Value 'config' ([ordered]@{kind='factory-uia-snapshot-worker-config-v1';outputRoot='worker-root';sourceBindings=$contract.sourceBindings;target=[ordered]@{lockOwner='owner'}})
$failed=[ordered]@{kind='factory-uia-snapshot-worker-exit-v1';status='failed';primaryError='Owned HWND closed during acquisition';timedOut=$false;cleanup=[ordered]@{kernelWaitResult=258;confirmedOwnedExit=$false;killAttempted=$true};ownedIdentity=[ordered]@{pid=$start.pid;path=$start.path;startedAt=$start.startedAt;retainedHandle=$start.retainedHandle};workerExeSha256=$start.workerExeHash;sourceContractSha256=$start.sourceContractHash;configSha256=$start.configHash;target=[ordered]@{lockOwner='owner'}}
$outHash=Store-Value 'original-failed' $failed
$cert=New-FactoryUiaFinalExitCertificate $sample $start $streams;$certHash=Store-Value 'certificate' $cert
$terminal=[ordered]@{kind='factory-uia-terminal-worker-v1';terminalResultConfirmed=$true;start=$start;finalCertificateRef='certificate';finalCertificateHash=$certHash;originalOutcomeRef='original-failed';originalOutcomeHash=$outHash}
$terminalHash=Store-Value 'terminal' $terminal
$expected=Copy-Value $start
foreach($pair in @(@('workerReceiptRef','terminal'),@('workerReceiptHash',$terminalHash),@('workerExeRef','exe'),@('sourceContractRef','contract'),@('configRef','config'),@('workerScriptRef','script'))){$expected|Add-Member -NotePropertyName $pair[0] -NotePropertyValue $pair[1]}
$expected|Add-Member -NotePropertyName sourceBindings -NotePropertyValue @([pscustomobject]@{path='worker.ps1';ref='script';sha256=$hash})
$reader={param($ref) if(-not $memory.ContainsKey($ref)){throw 'missing bytes'};return ,([byte[]]$memory[$ref])}
Check 'failed-original-byte-backed-release-proof' (Test-FactoryUiaFinalReleaseProof $cert $expected $reader)
Check 'all-owned-worker-proof' (Test-FactoryAllUiaWorkerReleaseProofs @('worker-root') @([pscustomobject]@{expected=$expected;certificate=$cert}) $reader)
Check 'original-failure-never-relabeled' ($failed.status -ceq 'failed' -and $failed.cleanup.kernelWaitResult -eq 258 -and $failed.cleanup.killAttempted)
$copy=Copy-Value $expected;$copy.sourceContractHash='a'*64;Check 'source-contract-corruption-holds' (-not(Test-FactoryUiaFinalReleaseProof $cert $copy $reader))
$memory['stdout']=[Text.Encoding]::UTF8.GetBytes('changed');Check 'raw-byte-corruption-holds' (-not(Test-FactoryUiaFinalReleaseProof $cert $expected $reader))
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh controls output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
$results|ConvertTo-Json -Depth 5|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
