# Windows x64 unsigned release candidate for SliceApp (right-git release-candidate lane, runs on windows-2025).
#   build   install the pinned Swift 6.4.0 toolchain, build SliceApp.exe, stage it with the pinned tuple 12 renderer, pack an
#           UNSIGNED MSIX (same manifest/virtualization/App Installer inputs as right-release.config.mjs), copy the evidence
#           to $env:RIGHT_GIT_ARTIFACT_ROOT\sliceapp\windows\x86_64
#   check   re-read the packed MSIX: hash vs seal, identity, no signature, payload, renderer byte-for-byte vs the pin
# Nothing here signs. Signing belongs to the windows-sign job (Azure Artifact Signing over OIDC), which is not provisioned yet.
param([ValidateSet('build', 'check')][string]$Action = 'build')
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$app = Join-Path $repo 'examples\SliceApp'
$outRoot = $env:RIGHT_GIT_ARTIFACT_ROOT
if (-not $outRoot) { throw 'RIGHT_GIT_ARTIFACT_ROOT is not set' }
$dest = Join-Path $outRoot 'sliceapp\windows\x86_64'
$msix = Join-Path $app 'dist\win\SliceApp_0.1.1.0_x64.msix'

# Swift 6.4.0 release installer from swift.org (the same toolchain line the Dell host uses: swift-6.4 RELEASE, x86_64-unknown-windows-msvc).
$swiftUrl = 'https://download.swift.org/swift-6.4.0-release/windows10/swift-6.4.0-RELEASE/swift-6.4.0-RELEASE-windows10.exe'
$swiftSha256 = '76169A85BCBA82854A0CD8F9655FFB74B3758D60C35A245457510095F2823C03'

function Fail([string]$m) { Write-Host "::error::$m"; throw $m }
function Step([string]$name, [scriptblock]$body) { Write-Host "::group::$name"; try { & $body } finally { Write-Host '::endgroup::' } }

function Merge-InstallerEnvironment {
    foreach ($level in 'Machine', 'User') {
        [Environment]::GetEnvironmentVariables($level).GetEnumerator() | ForEach-Object {
            if ($_.Name -eq 'Path') {
                $merged = ("$($env:Path);$($_.Value)" -split ';' | Where-Object { $_ } | Select-Object -Unique) -join ';'
                Set-Item -Path 'Env:Path' -Value $merged
            } else {
                Set-Item -Path "Env:$($_.Name)" -Value $_.Value
            }
        }
    }
}

function Install-Swift {
    $installer = Join-Path $env:RUNNER_TEMP 'swift-6.4.0-RELEASE-windows10.exe'
    if (-not (Test-Path $installer)) {
        Write-Host "downloading $swiftUrl"
        Invoke-WebRequest -Uri $swiftUrl -OutFile $installer
    }
    $actual = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
    Write-Host "swift installer sha256 $actual bytes $((Get-Item $installer).Length)"
    if ($actual -ne $swiftSha256.ToUpperInvariant()) { Fail "Swift installer sha256 $actual does not match the pin $swiftSha256" }
    $log = Join-Path $env:RUNNER_TEMP 'swift-install.log'
    $p = Start-Process -FilePath $installer -ArgumentList @('/quiet', '/norestart', '/log', $log) -Wait -PassThru
    Write-Host "swift installer exit code $($p.ExitCode)"
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
        if (Test-Path $log) { Get-Content $log -Tail 60 | ForEach-Object { Write-Host $_ } }
        Fail "Swift installer failed with exit code $($p.ExitCode)"
    }
    Merge-InstallerEnvironment
    $swift = Get-Command swift.exe -ErrorAction SilentlyContinue
    if (-not $swift) {
        foreach ($root in @((Join-Path $env:LOCALAPPDATA 'Programs\Swift'), (Join-Path $env:ProgramFiles 'Swift'))) {
            $hit = Get-ChildItem -Path (Join-Path $root 'Toolchains') -Recurse -Filter swift.exe -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($hit) { $env:Path = "$($hit.DirectoryName);$env:Path"; $swift = Get-Command swift.exe; break }
        }
    }
    if (-not $swift) { Fail 'swift.exe not found after the Swift installer ran' }
    Write-Host "swift.exe at $($swift.Source)"
    & swift.exe --version | Out-Host
    if ($LASTEXITCODE -ne 0) { Fail "swift --version exit $LASTEXITCODE" }
    # Runtimes\<version>\usr\bin is a sibling of Toolchains under the install root (swiftCore.dll marks it).
    $cursor = Split-Path $swift.Source
    $installRoot = $null
    while ($cursor -and (Split-Path $cursor)) {
        if ((Split-Path $cursor -Leaf) -eq 'Toolchains') { $installRoot = Split-Path $cursor; break }
        $cursor = Split-Path $cursor
    }
    if (-not $installRoot) { Fail "no Toolchains directory above $($swift.Source)" }
    $runtime = Get-ChildItem -Path (Join-Path $installRoot 'Runtimes') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'usr\bin' } | Where-Object { Test-Path (Join-Path $_ 'swiftCore.dll') } | Select-Object -First 1
    if (-not $runtime) { Fail "no Swift runtime directory (swiftCore.dll) under $installRoot\Runtimes" }
    Write-Host "swift runtime bin $runtime"
    return $runtime
}

if ($Action -eq 'build') {
    if ($swiftSha256 -like '__*') { Fail 'Swift installer sha256 pin is not set' }
    $runtimeBin = $null
    Step 'Install Swift 6.4.0' { $script:runtimeBin = Install-Swift }

    Step 'Prepare SliceApp configuration' {
        $cfg = Get-Content (Join-Path $app 'swift-package.json') -Raw | ConvertFrom-Json
        $cfg.windows.searchDirs = @($script:runtimeBin)
        $cfg | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $app 'swift-package.ci.json') -Encoding utf8
        $env:SWIFT_RUNTIME_BIN = $script:runtimeBin
        $env:RIGHT_RELEASE_CLI = Join-Path $repo 'node_modules\@rightkit\release\cli\right-release.mjs'
        if (-not (Test-Path $env:RIGHT_RELEASE_CLI)) { Fail "right-release not installed at $env:RIGHT_RELEASE_CLI (pnpm install at the repository root)" }
        $env:SWIFTRIGHT_RENDERER_SRC = Join-Path $repo 'probes\sr0-s\fresh-on-bridge\out\tuple13-renderer-ci-39173008419\swiftright-render-91400f36e48aa73145a2c50afc2743ab89fcf317\swiftright_render.dll'
    }

    Step 'Build, verify and stage (prepackage-windows.ps1: pre/post renderer pin check, ComCtl6 manifest, import closure, stage layout)' {
        & (Join-Path $app 'scripts\prepackage-windows.ps1') -Config 'swift-package.ci.json'
        if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { Fail "prepackage-windows failed (exit $LASTEXITCODE)" }
    }

    Step 'Pack unsigned MSIX' {
        Push-Location $repo
        try {
            & node (Join-Path $repo 'scripts\release\msix-unsigned.mjs')
            if ($LASTEXITCODE -ne 0) { Fail "msix-unsigned failed (exit $LASTEXITCODE)" }
        } finally { Pop-Location }
    }

    Step 'Collect evidence' {
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item -LiteralPath $msix $dest -Force
        Copy-Item -LiteralPath (Join-Path $app 'dist\win\msix-seal.json') $dest -Force
        Copy-Item -LiteralPath (Join-Path $app 'dist\win\SliceApp.appinstaller') (Join-Path $dest 'SliceApp.appinstaller.placeholder-uris') -Force
        Copy-Item -LiteralPath (Join-Path $app 'Windows\renderer-pin.json') $dest -Force
        $identity = [ordered]@{
            schema = 1
            sourceRevision = $env:RIGHT_GIT_SOURCE_REVISION
            platform = 'windows'; architecture = 'x86_64'; signed = $false
            swiftVersion = ((& swift.exe --version 2>&1) -join "`n")
            swiftInstallerSha256 = $swiftSha256.ToUpperInvariant()
            msixSha256 = (Get-FileHash -LiteralPath $msix -Algorithm SHA256).Hash.ToLowerInvariant()
            msixBytes = (Get-Item $msix).Length
            sliceAppExeSha256 = (Get-FileHash -LiteralPath (Join-Path $app '.build\payload\SliceApp.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
            rendererSha256 = (Get-FileHash -LiteralPath (Join-Path $app '.build\renderer\swiftright_render.dll') -Algorithm SHA256).Hash.ToLowerInvariant()
        }
        $identity | ConvertTo-Json | Set-Content (Join-Path $dest 'build-identity.json') -Encoding utf8
        Get-Content (Join-Path $dest 'build-identity.json')
    }
    exit 0
}

# check
Step 'Check unsigned MSIX candidate' {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $pin = Get-Content (Join-Path $app 'Windows\renderer-pin.json') -Raw | ConvertFrom-Json
    $candidate = Join-Path $dest 'SliceApp_0.1.1.0_x64.msix'
    if (-not (Test-Path $candidate)) { Fail "candidate MSIX missing: $candidate" }
    $seal = Get-Content (Join-Path $dest 'msix-seal.json') -Raw | ConvertFrom-Json
    $sha = (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sha -ne $seal.msix.sha256) { Fail "msix sha256 $sha differs from the seal $($seal.msix.sha256)" }
    if ($seal.signed) { Fail 'seal says signed: this lane must produce an unsigned candidate' }
    $unpack = Join-Path $env:RUNNER_TEMP 'msix-check'
    Remove-Item -Recurse -Force $unpack -ErrorAction SilentlyContinue
    $zip = [System.IO.Compression.ZipFile]::OpenRead($candidate)
    try {
        $names = $zip.Entries | ForEach-Object { $_.FullName }
        foreach ($required in 'AppxManifest.xml', 'SliceApp.exe', $pin.file) { if ($names -notcontains $required) { Fail "MSIX payload lacks $required" } }
        if ($names -contains 'AppxSignature.p7x') { Fail 'MSIX carries AppxSignature.p7x: not an unsigned candidate' }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($candidate, $unpack)
    } finally { $zip.Dispose() }
    [xml]$manifest = Get-Content (Join-Path $unpack 'AppxManifest.xml') -Raw
    $id = $manifest.Package.Identity
    if ($id.Name -ne 'OrthicLabs.SliceApp' -or $id.Version -ne '0.1.1.0' -or $id.ProcessorArchitecture -ne 'x64') { Fail "unexpected identity: $($id.Name) $($id.Version) $($id.ProcessorArchitecture)" }
    $payloadRenderer = (Get-FileHash -LiteralPath (Join-Path $unpack $pin.file) -Algorithm SHA256).Hash
    if ($payloadRenderer -ne $pin.sha256.ToUpperInvariant()) { Fail "renderer in the MSIX is $payloadRenderer, pin is $($pin.sha256)" }
    Write-Host "renderer in MSIX payload matches the tuple 12 pin $payloadRenderer"
    & (Join-Path $app 'scripts\verify-package-layout.ps1') -Mode Stage -Root $unpack
    if ($LASTEXITCODE -ne 0 -and $null -ne $LASTEXITCODE) { Fail "verify-package-layout (unpacked MSIX) failed (exit $LASTEXITCODE)" }
    Write-Host "unsigned MSIX candidate ok: sha256 $sha, identity $($id.Name) $($id.Version) $($id.ProcessorArchitecture)"
}
