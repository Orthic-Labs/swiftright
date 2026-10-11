<#
Create an isolated tuple12 source candidate from a clean base clone & apply only
qualification/tuple12-startupguard-overlay.json. No remote build, GUI, runner,
delete, or reuse of an existing candidate is performed. The caller owns later
Windows staging/build effects.
#>
param(
  [Parameter(Mandatory = $true)][string]$BaseSource,
  [Parameter(Mandatory = $true)][string]$OverlaySource,
  [Parameter(Mandatory = $true)][string]$OverlayManifest,
  [Parameter(Mandatory = $true)][string]$ExpectedOverlaySha256,
  [Parameter(Mandatory = $true)][string]$CandidateSource,
  [Parameter(Mandatory = $true)][string]$RendererDll,
  [Parameter(Mandatory = $true)][string]$ExpectedRendererSha256,
  [Parameter(Mandatory = $true)][string]$RendererReceipt,
  [string]$CandidateManifest = ''
)
$ErrorActionPreference = 'Stop'
$script:Step = 'init'
function Need([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing file: $Path" }
}
function NeedDir([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "missing directory: $Path" }
}
function Sha([string]$Path) {
  Need $Path
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Checked([string]$Exe, [string[]]$Args, [string]$Name) {
  $script:Step = $Name
  & $Exe @Args 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "$Name failed with exit $LASTEXITCODE" }
}
function SafeChild([string]$Root, [string]$Relative) {
  if ([IO.Path]::IsPathRooted($Relative)) { throw "overlay path is rooted: $Relative" }
  $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
  $candidate = [IO.Path]::GetFullPath((Join-Path $Root ($Relative -replace '/', '\')))
  if (-not $candidate.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) { throw "overlay path escapes candidate: $Relative" }
  return $candidate
}
try {
  $script:Step = 'preflight'
  NeedDir $BaseSource
  NeedDir $OverlaySource
  Need $OverlayManifest
  Need $RendererDll
  Need $RendererReceipt
  if ((Sha $OverlayManifest) -ne $ExpectedOverlaySha256.ToLowerInvariant()) { throw 'overlay manifest hash mismatch' }
  if ((Sha $RendererDll) -ne $ExpectedRendererSha256.ToLowerInvariant()) { throw 'renderer hash mismatch' }
  $baseGit = Join-Path $BaseSource '.git'
  NeedDir $baseGit
  $manifest = Get-Content -LiteralPath $OverlayManifest -Raw | ConvertFrom-Json
  if ([string]$manifest.baseSourceCommit -notmatch '^[0-9a-fA-F]{40}$') { throw 'overlay baseSourceCommit must be full SHA-1' }
  $baseHead = (& git -C $BaseSource rev-parse HEAD 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0 -or $baseHead -ne ([string]$manifest.baseSourceCommit).ToLowerInvariant()) { throw "base source HEAD mismatch: $baseHead" }
  $baseStatus = (& git -C $BaseSource status --porcelain --untracked-files=no 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'base source status failed' }
  if ($baseStatus) { throw 'base source has tracked changes' }
  if (-not $manifest.files -or @($manifest.files).Count -lt 1) { throw 'overlay has no files' }
  if ((Test-Path -LiteralPath $CandidateSource) -or (Test-Path -LiteralPath $CandidateSource -PathType Container)) { throw "candidate already exists: $CandidateSource" }
  $candidateParent = Split-Path -Parent ([IO.Path]::GetFullPath($CandidateSource))
  NeedDir $candidateParent

  $script:Step = 'clone-candidate'
  Checked 'git' @('clone', '--no-local', '--no-hardlinks', '--no-checkout', $BaseSource, $CandidateSource) 'clone-candidate'
  Checked 'git' @('-C', $CandidateSource, 'checkout', '--detach', ([string]$manifest.baseSourceCommit)) 'checkout-candidate'

  $records = @()
  foreach ($entry in @($manifest.files)) {
    $rel = [string]$entry.path
    $overlayPath = SafeChild $OverlaySource $rel
    $candidatePath = SafeChild $CandidateSource $rel
    Need $overlayPath
    $actualOverlaySha = Sha $overlayPath
    if ($actualOverlaySha -ne ([string]$entry.sha256).ToLowerInvariant()) { throw "overlay file hash mismatch: $rel" }
    $expectedBaseSha = if ($null -eq $entry.base_sha256) { '' } else { [string]$entry.base_sha256 }
    $candidateExists = Test-Path -LiteralPath $candidatePath -PathType Leaf
    if ($expectedBaseSha) {
      if (-not $candidateExists -or (Sha $candidatePath) -ne $expectedBaseSha.ToLowerInvariant()) { throw "base file hash mismatch: $rel" }
    } elseif ($candidateExists) {
      throw "added overlay file already exists in base: $rel"
    }
    $parent = Split-Path -Parent $candidatePath
    New-Item -ItemType Directory -Force -Path $parent -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $overlayPath -Destination $candidatePath -Force -ErrorAction Stop
    if ((Sha $candidatePath) -ne $actualOverlaySha) { throw "candidate copy hash mismatch: $rel" }
    $records += [ordered]@{ path = $rel; sha256 = $actualOverlaySha; bytes = (Get-Item -LiteralPath $candidatePath).Length; base_sha256 = if ($expectedBaseSha) { $expectedBaseSha.ToLowerInvariant() } else { $null } }
  }
  $status = (& git -C $CandidateSource status --porcelain --untracked-files=all 2>&1 | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) { throw 'candidate status failed' }
  $candidateManifestPath = if ($CandidateManifest) { [IO.Path]::GetFullPath($CandidateManifest) } else { Join-Path $CandidateSource 'tuple12-source-overlay-manifest.json' }
  if (Test-Path -LiteralPath $candidateManifestPath) { throw "candidate manifest already exists: $candidateManifestPath" }
  $candidateRecord = [ordered]@{
    kind = 'sr0-tuple12-startupguard-source-candidate-v1'
    status = 'overlay-applied-source-only'
    baseSourceCommit = ([string]$manifest.baseSourceCommit).ToLowerInvariant()
    overlayManifestSha256 = (Sha $OverlayManifest)
    rendererSha256 = (Sha $RendererDll)
    rendererReceipt = [IO.Path]::GetFullPath($RendererReceipt)
    candidateSource = [IO.Path]::GetFullPath($CandidateSource)
    files = $records
    gitStatus = $status
    remoteActions = 0
    nativeActions = 0
    guiActions = 0
    deleteActions = 0
  }
  $candidateManifestParent = Split-Path -Parent $candidateManifestPath
  New-Item -ItemType Directory -Force -Path $candidateManifestParent -ErrorAction Stop | Out-Null
  $candidateRecord | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $candidateManifestPath -Encoding UTF8 -ErrorAction Stop
  Write-Output "SOURCE_CANDIDATE_OK base=$($candidateRecord.baseSourceCommit) overlay=$($candidateRecord.overlayManifestSha256) renderer=$($candidateRecord.rendererSha256) path=$CandidateSource manifest=$candidateManifestPath"
} catch {
  Write-Output "SOURCE_CANDIDATE_FAILED step=$($script:Step): $($_.Exception.Message)"
  throw
}
