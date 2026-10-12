param([Parameter(Mandatory=$true)][string]$ControlRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'assert-count20-count1-certificate.ps1')
function New-CertificateFixture([string]$Name){
 $root=Join-Path $ControlRoot ('count1-certificate-'+$Name+'-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Force -Path $root|Out-Null;$path=Join-Path $root 'coordinator.json'
 $doc=[ordered]@{kind='root-rectangle-count1-coordinator-v1';status='completed-source-bound-observation';count=1;owner='control-owner';wholeBatchExitConfirmed=$true;lockReleased=$true;error='';cleanupErrors=@();taskParentProof=[ordered]@{pid=101;retainedHandle=202;kernelWait=0;kernelExitCode=0;kernelExitCodeSigned=0;dotNetExited=$true;dotNetExitCode=0}}
 $doc|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $path -Encoding UTF8
 $item=Get-Count20CertificateItem $path;[pscustomobject]@{path=$path;bytes=[int64]$item.Length;hash=(Get-Count20CertificateHash $path);doc=$doc}
}
New-Item -ItemType Directory -Force -Path $ControlRoot|Out-Null
$positive=New-CertificateFixture 'positive';Assert-Count20OriginalCount1Certificate $positive.path $positive.hash $positive.bytes|Out-Null
$faults=@(
 @{name='wrong-status';mutate={param($c);$c.doc.status='failed'}},
 @{name='whole-batch-false';mutate={param($c);$c.doc.wholeBatchExitConfirmed=$false}},
 @{name='lock-release-false';mutate={param($c);$c.doc.lockReleased=$false}},
 @{name='kernel-nonzero';mutate={param($c);$c.doc.taskParentProof.kernelExitCode=1}},
 @{name='dotnet-nonzero';mutate={param($c);$c.doc.taskParentProof.dotNetExitCode=1}},
 @{name='missing-parent-field';mutate={param($c);$c.doc.taskParentProof.PSObject.Properties.Remove('retainedHandle')}
 }
)
foreach($fault in $faults){$case=New-CertificateFixture $fault.name;& $fault.mutate $case;$case.doc|ConvertTo-Json -Depth 12|Set-Content -LiteralPath $case.path -Encoding UTF8;$bytes=[int64](Get-Count20CertificateItem $case.path).Length;$hash=Get-Count20CertificateHash $case.path;$rejected=$false;try{Assert-Count20OriginalCount1Certificate $case.path $hash $bytes|Out-Null}catch{$rejected=$true};if(-not $rejected){throw ('Count1 certificate fault accepted: '+$fault.name)}}
Write-Output 'SOURCE_CONTROLS_PASS count20-count1-certificate'
