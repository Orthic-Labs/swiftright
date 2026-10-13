# Non-mutating entry: reads archived proof inputs & invokes prospective release predicate.
param(
 [Parameter(Mandatory=$true)][string]$Directory,
 [Parameter(Mandatory=$true)][string]$Owner,
 [Parameter(Mandatory=$true)][string]$CompilePath,
 [Parameter(Mandatory=$true)][string]$CompileHash,
 [Parameter(Mandatory=$true)][string]$Exe,
 [Parameter(Mandatory=$true)][string]$ExeHash,
 [Parameter(Mandatory=$true)][string]$SourceHash,
 [Parameter(Mandatory=$true)][string]$ProducerRoot,
 [Parameter(Mandatory=$true)]$SourceInputs
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
. (Join-Path $ProducerRoot 'support\final-exit-certificate.ps1')
. (Join-Path $ProducerRoot 'dependencies\uia-worker\support\final-exit-certificate.ps1')
. (Join-Path $PSScriptRoot 'final-exit-certificate-mta-v1.ps1')
. (Join-Path $PSScriptRoot 'all-owned-release-rectangle-mta-v1.ps1')
Assert-RootRectangleAllOwnedReleaseMta $Directory $Owner $CompilePath $CompileHash $Exe $ExeHash $SourceHash $ProducerRoot $SourceInputs
