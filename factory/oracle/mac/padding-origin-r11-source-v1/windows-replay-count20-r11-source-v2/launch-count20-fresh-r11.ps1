# Root-controlled Count20 launch recipe for fresh r11 namespace.
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$IssuedMetadataPath,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$IssuedMetadataHash,
 [Parameter(Mandatory=$true)][string]$GuardControlsPath,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$GuardControlsHash,
 [Parameter(Mandatory=$true)][string]$FreshTuplePath,[Parameter(Mandatory=$true)][string]$FreshManifestPath,[Parameter(Mandatory=$true)][string]$EquivalencePath,
 [Parameter(Mandatory=$true)][string]$OverlayStageManifestPath,[Parameter(Mandatory=$true)][string]$CoordinatorPath,
 [Parameter(Mandatory=$true)][string]$RunRoot,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CompileReceiptSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ExeSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SerializerControlSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$EquivalenceSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FreshTupleSha256,[Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$FreshManifestSha256,
 [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-f]{64}$')][string]$OverlayStageSha256
)
$ErrorActionPreference='Stop';function Hash([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()};function Require([string]$p){if(-not(Test-Path -LiteralPath $p -PathType Leaf)){throw "Missing launch input: $p"}}
foreach($p in @($IssuedMetadataPath,$GuardControlsPath,$FreshTuplePath,$FreshManifestPath,$EquivalencePath,$OverlayStageManifestPath,$CoordinatorPath)){Require $p}
if((Hash $IssuedMetadataPath) -cne $IssuedMetadataHash -or (Hash $GuardControlsPath) -cne $GuardControlsHash -or (Hash $FreshTuplePath) -cne $FreshTupleSha256 -or (Hash $FreshManifestPath) -cne $FreshManifestSha256 -or (Hash $EquivalencePath) -cne $EquivalenceSha256 -or (Hash $OverlayStageManifestPath) -cne $OverlayStageSha256){throw 'Launch input hash drift'}
$eq=Get-Content -Raw $EquivalencePath|ConvertFrom-Json;$guard=Get-Content -Raw $GuardControlsPath|ConvertFrom-Json;$stage=Get-Content -Raw $OverlayStageManifestPath|ConvertFrom-Json;$m=Get-Content -Raw $IssuedMetadataPath|ConvertFrom-Json
if($eq.status -cne 'reuse-admitted-source-equivalent-v4' -or $eq.candidateOnly -ne $true -or $eq.requirements.freshMetadata -ne $true -or $eq.requirements.freshCaptureIDs -ne $true){throw 'v4 candidate gate not admitted'}
if($guard.kind -cne 'factory-fresh-count20-r11-guard-controls-v1' -or $guard.status -cne 'passed-source-only' -or $guard.count -ne 20 -or $guard.issuedMetadataSha256 -cne $IssuedMetadataHash -or $guard.baseline.accepted -ne $true -or $guard.nativeWindowActions -ne 0 -or $guard.compilerActions -ne 0 -or $guard.guiActions -ne 0 -or $guard.remoteActions -ne 0 -or $guard.lockActions -ne 0){throw 'Fresh guard controls not admitted'}
if($m.expectedCount -ne 20 -or $m.frozenTupleBound -ne $false -or $m.captures.Count -ne 20 -or [IO.Path]::GetFullPath($m.runRoot) -cne [IO.Path]::GetFullPath($RunRoot)){throw 'Fresh metadata launch join mismatch'}
if($stage.kind -ne 'factory-repeat-r7-source-stage-manifest-v1' -or $stage.controls.nativeActions -ne 0 -or $stage.controls.lockActions -ne 0 -or $stage.controls.compilerActions -ne 0){throw 'Repeat-r7 stage controls not admitted'}
foreach($f in $stage.files){if(-not(Test-Path -LiteralPath $f.path -PathType Leaf)){throw ('Repeat-r7 source missing: '+$f.path)};if((Hash $f.path) -cne $f.sha256.Replace('sha256:','')){throw ('Repeat-r7 source drift: '+$f.path)}}
if(Test-Path $RunRoot){throw 'Fresh Count20 run namespace already exists'}
# CoordinatorPath must point to reviewed fresh namespace-aware coordinator; this recipe never substitutes donor paths.
& $CoordinatorPath -IssuedMetadataPath $IssuedMetadataPath -IssuedMetadataHash $IssuedMetadataHash -RunRoot $RunRoot -CompileReceiptHash $CompileReceiptSha256 -ExeHash $ExeSha256 -SerializerControlSha256 $SerializerControlSha256 -Count 20
