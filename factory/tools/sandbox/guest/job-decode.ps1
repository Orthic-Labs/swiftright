# job-decode.ps1 - kind=decode (wave 0 block I1). args: {"exe":"D:\\...\\ImageDump.exe","corpus":"D:\\...\\corpus","runs":N,"old":true}.
# Runs the console decode-dump host N times, each time in a fresh process: ImageDump CORPUS OUT\run-NN (the first run also --old: the pure-Swift block 35 decoder). Per run the dump
# (results.json + run.bin) lands as <JobDir>\out\run-NN.zip with the run.bin SHA-256 recorded in result.json. No window, no renderer, no capture lease: WIC decoding only.
# Swift runtime DLLs come from C:\swiftrt via PATH; the exe and the corpus are read through the mapped D: drive.
param([Parameter(Mandatory)][string]$JobDir)
$ErrorActionPreference = 'Stop'
$job = Get-Content -LiteralPath "$JobDir\job.json" -Raw | ConvertFrom-Json
$runs = $(if ($job.args.runs) { [int]$job.args.runs } else { 1 })
$res = [ordered]@{ kind = 'decode'; ok = $false; runs = $runs; exe_source = [string]$job.args.exe }
try {
    $env:Path = 'C:\swiftrt;' + $env:Path
    $src = [string]$job.args.exe; $corpus = [string]$job.args.corpus
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw "exe not visible in the guest: $src" }
    if (-not (Test-Path -LiteralPath "$corpus\manifest.json")) { throw "corpus not visible in the guest: $corpus" }
    $work = 'C:\work\' + (Split-Path -Leaf $JobDir)
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    Get-ChildItem -LiteralPath (Split-Path -Parent $src) -File | Where-Object { $_.Extension -in '.exe', '.dll' } | Copy-Item -Destination $work -Force
    $exe = Join-Path $work (Split-Path -Leaf $src)
    $res.exe_sha256 = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLower()
    $res.os = [string][Environment]::OSVersion.Version
    try { $res.windowscodecs = (Get-Item C:\Windows\System32\WindowsCodecs.dll).VersionInfo.FileVersion } catch { }
    $out = "$JobDir\out"; New-Item -ItemType Directory -Force -Path $out | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ($job.args.env) { foreach ($p in $job.args.env.PSObject.Properties) { Set-Item -Path ('Env:' + $p.Name) -Value ([string]$p.Value) } }   # e.g. SWIFTRIGHT_WIC_INTENT for the rendering-intent measurement
    $per = @()
    for ($i = 1; $i -le $runs; $i++) {
        $n = '{0:D2}' -f $i
        $dir = "$work\run-$n"
        $args2 = @($corpus, $dir); if ($i -eq 1 -and $job.args.old) { $args2 += '--old' }
        $ErrorActionPreference = 'Continue'   # WIC's JPEG decoder writes libjpeg warnings ("Corrupt JPEG data: premature end of data segment") to stderr for a cut file: not an error of the job
        $o = (& $exe @args2 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
        $ec = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        $sha = $null
        if (Test-Path -LiteralPath "$dir\run.bin") { $sha = (Get-FileHash -LiteralPath "$dir\run.bin" -Algorithm SHA256).Hash.ToLower() }
        if (Test-Path -LiteralPath $dir) { [IO.Compression.ZipFile]::CreateFromDirectory($dir, "$out\run-$n.zip") }
        $per += [ordered]@{ run = $i; exit = $ec; runbin_sha256 = $sha; stdout = $o.Trim() }
    }
    $res.per_run = $per
    $res.ok = [bool](@($per | Where-Object { $_.exit -ne 0 -or -not $_.runbin_sha256 }).Count -eq 0)
} catch { $res.error = $_.Exception.Message }
[IO.File]::WriteAllText("$JobDir\result.json", (ConvertTo-Json -InputObject $res -Depth 6), (New-Object Text.UTF8Encoding($false)))
exit 0
