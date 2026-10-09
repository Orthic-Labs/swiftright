# Independent clean clone build for SliceApp (Windows host; run through `win`). RightKit requires a branch-attached
# PRIMARY checkout; a linked worktree does not qualify (release-invocation.mjs assertPrimaryReleaseCheckout), so the
# build runs in a fresh `git clone` of origin at an exact commit, outside any existing checkout.
#
#   win "powershell -NoProfile -ExecutionPolicy Bypass -File <path>\clone-build-win.ps1 -Commit <sha> [-DryRun]"
#
#   -Commit          required; 7-40 hex chars, resolved to the full SHA after fetch
#   -Origin          default git@github.com:bogusyogi/swiftright.git
#   -Scratch         default D:\Claude\swiftright-clean\<sha12>
#   -RightKit        default D:\Claude\rightkit (local @rightkit/release package; read-only use)
#   -RendererSource  swiftright_render.dll to stage (default: $env:SWIFTRIGHT_RENDERER_SRC, else the pin's defaultSource);
#                    prepackage-windows.ps1 hash-checks it against Windows\renderer-pin.json and fails closed
#   -Stage           doctor | qa | build (default build; seal, NO upload). `qa` runs `right-release qa --stage source` (release gate,
#                    @rightkit/release >= 0.2.144): build refuses without its passing receipt for the same commit, so run `qa` first
#                    in the same clone. rightkit-qa must be on PATH. QA launches SliceApp windows: needs a free interactive desktop.
#   -DryRun          parse and validate arguments, print the plan, touch nothing
# Never runs upload/publish-update. The commit must already be pushed to origin.
#
# package.json pins @rightkit/release as link:../../../rightkit/packages/release (relative to examples\SliceApp).
# The clone sits at <scratch>\swiftright and <scratch>\rightkit is a junction to -RightKit, so the link resolves
# without editing a tracked file (the tree stays clean, as the source gate requires).
param(
    [string]$Commit = '',
    [string]$Origin = 'git@github.com:bogusyogi/swiftright.git',
    [string]$Scratch = '',
    [string]$RightKit = 'D:\Claude\rightkit',
    [string]$RendererSource = '',
    [ValidateSet('doctor', 'qa', 'build')][string]$Stage = 'build',
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
function Fail([string]$m) { [Console]::Error.WriteLine("clone-build-win: $m"); exit 2 }
if (-not $Commit) { Fail '-Commit is required' }
if ($Commit -notmatch '^[0-9a-fA-F]{7,40}$') { Fail '-Commit must be 7-40 hex characters' }
$short = $Commit.Substring(0, [Math]::Min(12, $Commit.Length))
if (-not $Scratch) { $Scratch = "D:\Claude\swiftright-clean\$short" }
$Scratch = [IO.Path]::GetFullPath($Scratch)
$primary = & { $ErrorActionPreference = 'Continue'; git -C $PSScriptRoot rev-parse --show-toplevel 2>$null }
if ($primary) {
    $p = [IO.Path]::GetFullPath(($primary -replace '/', '\')).TrimEnd('\') + '\'
    if (($Scratch.TrimEnd('\') + '\').StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { Fail "-Scratch must be outside the primary checkout ($primary)" }
}
$branch = "sr0-clean-$short"
$clone = Join-Path $Scratch 'swiftright'
"plan: clone $Origin at $Commit -> $clone (branch $branch)"
"plan: $Scratch\rightkit -> $RightKit (junction)"
"plan: examples\SliceApp: pnpm install --frozen-lockfile; pnpm exec right-release $Stage --platform win --config right-release.config.mjs"
if ($RendererSource) { "plan: renderer source $RendererSource (SWIFTRIGHT_RENDERER_SRC)" }
if ($DryRun) { 'dry-run: nothing executed'; exit 0 }

if (-not (Test-Path (Join-Path $RightKit 'packages\release'))) { Fail "RightKit release package not found: $RightKit\packages\release" }
if (Test-Path $clone) { Fail "$clone already exists; pick a new -Scratch or remove it yourself" }
New-Item -ItemType Directory -Force (Join-Path $Scratch 'tools') | Out-Null
New-Item -ItemType Junction -Path (Join-Path $Scratch 'rightkit') -Target $RightKit | Out-Null

function Run([string]$exe, [string[]]$a) { & $exe @a; if ($LASTEXITCODE -ne 0) { throw "$exe $($a -join ' ') failed (exit $LASTEXITCODE)" } }
Run git @('clone', '--no-checkout', $Origin, $clone)
Set-Location $clone
& { $ErrorActionPreference = 'Continue'; git fetch origin $Commit 2>$null }
$full = (& git rev-parse --verify "$Commit^{commit}")
if ($LASTEXITCODE -ne 0 -or -not $full) { throw "commit $Commit is not available from $Origin (push it first)" }
Run git @('checkout', '-q', '-B', $branch, $full)
if ((& git rev-parse HEAD) -ne $full) { throw "HEAD is not $full after checkout" }
if (& git status --porcelain) { throw 'fresh clone is not clean' }
"clone at $full on branch $branch"

Set-Location (Join-Path $clone 'examples\SliceApp')
if ($RendererSource) { $env:SWIFTRIGHT_RENDERER_SRC = $RendererSource }
Run pnpm @('install', '--frozen-lockfile')
if (& git status --porcelain) { throw 'pnpm install dirtied the tree (lockfile out of date?); source gate would refuse' }
if ($Stage -eq 'doctor') { Run pnpm @('exec', 'right-release', 'doctor', '--platform', 'win', '--config', 'right-release.config.mjs') }
elseif ($Stage -eq 'qa') { Run pnpm @('exec', 'right-release', 'qa', '--stage', 'source', '--platform', 'win', '--config', 'right-release.config.mjs') }
else { Run pnpm @('exec', 'right-release', 'build', '--platform', 'win', '--config', 'right-release.config.mjs') }
"done: $Stage at $full (clone: $clone). Artifacts under $clone\examples\SliceApp\dist and the RightKit state root."
