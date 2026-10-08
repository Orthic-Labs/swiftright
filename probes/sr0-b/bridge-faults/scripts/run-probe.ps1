# SR0-B bridge-faults driver (runs on Windows x64 under D:\Claude\sr0b-bridge-faults).
# Stage 1: build renderer variants (MSVC) and the Swift host (SwiftPM).
# Stage 2: run the startup matrix (missing / major mismatch / table mismatch / matching) and the full tests, 3 times.
param([string]$Stage = 'all', [int]$Runs = 3)
$ErrorActionPreference = 'Stop'
$root = 'D:\Claude\sr0b-bridge-faults'
$swiftBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$rtBin = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin'

& 'C:\Program Files\Microsoft Visual Studio\18\Community\Common7\Tools\Launch-VsDevShell.ps1' -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
$env:Path = "$swiftBin;$rtBin;" + $env:Path

$inc = "$root\Sources\CSwrFakeRender"
$src = "$root\renderer\swr_fake_render.c"

if ($Stage -eq 'all' -or $Stage -eq 'build') {
    function Build-Variant([string]$name, [string[]]$defs) {
        $out = "$root\variants\$name"
        New-Item -ItemType Directory -Force $out | Out-Null
        $args2 = @('/nologo', '/LD', '/W4', '/WX', '/DSWR_BUILD') + $defs + @("/I$inc", $src, "/Fe$out\swr_fake_render.dll", "/Fo$out\swr_fake_render.obj", '/link', "/IMPLIB:$out\swr_fake_render.lib")
        & cl @args2
        if ($LASTEXITCODE -ne 0) { throw "cl failed for variant $name (exit $LASTEXITCODE)" }
        Write-Output "variant $name built: $out\swr_fake_render.dll"
    }
    Build-Variant 'match' @()
    Build-Variant 'major' @('/DSWR_REPORT_MAJOR=1')
    Build-Variant 'table' @('/DSWR_EXTRA_CB_SLOT')
    New-Item -ItemType Directory -Force "$root\variants\missing" | Out-Null

    Set-Location -LiteralPath $root
    & swift build -c release --scratch-path "$root\scratch-b1"
    if ($LASTEXITCODE -ne 0) { throw "swift build failed (exit $LASTEXITCODE)" }
    $bin = (& swift build -c release --scratch-path "$root\scratch-b1" --show-bin-path).Trim()
    Write-Output "swift build ok; bin path: $bin"
}

if ($Stage -eq 'all' -or $Stage -eq 'run') {
    Set-Location -LiteralPath $root
    $bin = (& swift build -c release --scratch-path "$root\scratch-b1" --show-bin-path).Trim()
    $exe = "$bin\BridgeFaults.exe"
    $cases = @(
        @{ name = 'missing-dll'; dll = "$root\variants\missing\swr_fake_render.dll" },
        @{ name = 'major-mismatch'; dll = "$root\variants\major\swr_fake_render.dll" },
        @{ name = 'table-mismatch'; dll = "$root\variants\table\swr_fake_render.dll" },
        @{ name = 'matching'; dll = "$root\variants\match\swr_fake_render.dll" }
    )
    for ($run = 1; $run -le $Runs; $run++) {
        foreach ($c in $cases) {
            Write-Output "=== run $run case $($c.name) ==="
            $out = & $exe $c.dll 2>&1
            $code = $LASTEXITCODE
            $out | ForEach-Object { Write-Output $_ }
            Write-Output "exit=$code"
        }
    }
}
