[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$ProducerRoot,
 [Parameter(Mandatory=$true)][string]$OverlayRoot,
 [Parameter(Mandatory=$true)][string]$SourceInputsPath
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $OverlayRoot 'diagnostic-profile-root-v10.ps1')
if(-not(Test-Path -LiteralPath $SourceInputsPath -PathType Leaf)){throw 'cleanup control source-inputs missing'}
$si=Get-DiagnosticJson $SourceInputsPath
Assert-CircleDiagnosticSourceInputs ([IO.Path]::GetFullPath($ProducerRoot)) $si|Out-Null
$callerNames=@('capture-circle-diagnostic-single-v10.ps1','dispatch-circle-diagnostic-single-v10.ps1')
foreach($name in $callerNames){$p=Join-Path $OverlayRoot $name;if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw ('cleanup caller missing '+$name)};$t=Get-Content -LiteralPath $p -Raw;if($t -match 'FactoryProcessWaitV5' -or $t -notmatch 'support[\\/]cleanup\.ps1' -or $t -notmatch 'Invoke-FactoryOwnedCleanup'){throw ('cleanup caller closure drift '+$name)}}
$mta=Join-Path $ProducerRoot 'dependencies\uia-worker\invoke-worker-mta.ps1';$mt=Get-Content -LiteralPath $mta -Raw;if($mt -match 'FactoryProcessWaitV5' -or $mt -notmatch 'support[\\/]cleanup\.ps1' -or $mt -notmatch 'Invoke-FactoryOwnedCleanup'){throw 'UIA cleanup caller closure drift'}
$cleanupPaths=@((Join-Path $ProducerRoot 'support\cleanup.ps1'),$mta.Replace('invoke-worker-mta.ps1','support\cleanup.ps1'));foreach($cleanupPath in $cleanupPaths){$cleanupText=Get-Content -LiteralPath $cleanupPath -Raw;if(-not $cleanupText.Contains('FactoryProcessWaitV6') -or $cleanupText.Contains('FactoryProcessWaitV5')){throw ('cleanup V6 ABI closure drift: '+$cleanupPath)}}
function Copy-Si([object]$Value){$Value|ConvertTo-Json -Depth 64|ConvertFrom-Json}
function Reject-Cleanup([string]$Name,[scriptblock]$Mutate){$x=Copy-Si $si;& $Mutate $x;$rejected=$false;try{Assert-CircleDiagnosticSourceInputs ([IO.Path]::GetFullPath($ProducerRoot)) $x|Out-Null}catch{$rejected=$true};if(-not $rejected){throw ('cleanup fault accepted: '+$Name)};[ordered]@{name=$Name;rejected=$true}}
$faults=@()
$faults+=Reject-Cleanup 'missing-renderer-role' {$args[0].cleanupV2.renderer=$null}
$faults+=Reject-Cleanup 'missing-uia-role' {$args[0].cleanupV2.uia=$null}
$faults+=Reject-Cleanup 'wrong-renderer-hash' {$args[0].cleanupV2.renderer.sha256='sha256:'+'0'*64}
$faults+=Reject-Cleanup 'wrong-uia-hash' {$args[0].cleanupV2.uia.sha256='sha256:'+'0'*64}
$faults+=Reject-Cleanup 'wrong-helper-kind' {$args[0].cleanupHelperKind='factory-child-kernel-cleanup-v2'}
$faults+=Reject-Cleanup 'wrong-helper-sha' {$args[0].cleanupHelperSha256='0'*64}
$faults+=Reject-Cleanup 'reordered-helper-paths' {$args[0].cleanupHelperPaths=@($args[0].cleanupHelperPaths[1],$args[0].cleanupHelperPaths[0])}
if(@($faults).Count -ne 7){throw 'unexpected cleanup fault count'}
[ordered]@{kind='factory-circle-cleanup-helper-controls-v1';status='SOURCE_CLEANUP_HELPER_CONTROLS_PASS';helperKind=$si.cleanupHelperKind;helperSha256=$si.cleanupHelperSha256;roles=2;faults=$faults;faultCount=$faults.Count;nativeActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json -Depth 12
