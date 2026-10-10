# Factory-only compile/layout collection. No visible console/window or desktop lock action.
param([Parameter(Mandatory=$true)][string]$Package)
$ErrorActionPreference = 'Stop'
$factory = 'D:\Claude\swiftright\factory\native\windows\'
$packagePath = [IO.Path]::GetFullPath($Package)
if (-not $packagePath.StartsWith($factory, [StringComparison]::OrdinalIgnoreCase)) { throw 'Package outside factory lane' }
function Wait-Owned($process, [int]$milliseconds) {
    if (-not $process.WaitForExit($milliseconds)) {
        & taskkill /PID $process.Id /T /F | Out-Null
        throw 'Owned factory child exceeded deadline'
    }
}
$plan = Get-Content -Raw (Join-Path $packagePath 'plan.json') | ConvertFrom-Json
if ($plan.stage -ne 'D:\Claude\sr0-r10') { throw 'Unexpected stage' }
if ($plan.rendererSha256 -ne 'e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93') { throw 'Unexpected renderer pin' }
$runtimePath=[IO.Path]::GetFullPath($plan.runtimePackagePath)
if($runtimePath -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\' -or $plan.runtimeSourceCommit -eq '8e47b89b3e9ae488e77ea8b5a2e4663053601c0d'){throw 'Distinct owned additive runtime required'}
if((Get-FileHash -LiteralPath (Join-Path $packagePath 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'Runtime receipt drift'}
. (Join-Path $PSScriptRoot 'verify-runtime-source.ps1')
Assert-FactoryRuntimeSource $plan $packagePath
$runtimeReceipt=Get-Content -Raw (Join-Path $packagePath 'runtime-source-receipt.json')|ConvertFrom-Json
if($runtimeReceipt.synthetic -or $plan.synthetic){throw 'Synthetic runtime cannot enter actual compiler lane'}
$dll = Join-Path $plan.stage 'renderer\swiftright_render.dll'
if ((Get-FileHash -LiteralPath $dll).Hash.ToLowerInvariant() -ne $plan.rendererSha256) { throw 'Staged DLL drift' }
foreach ($binding in $plan.sourceBindings) {
    $sourceInput = [IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
    if (-not $sourceInput.StartsWith($packagePath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Source binding escapes package' }
    if ((Get-FileHash -LiteralPath $sourceInput).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:', '')) { throw 'Factory source drift' }
}
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + $env:Path
$stdout = Join-Path $packagePath 'compile.stdout.txt'
$stderr = Join-Path $packagePath 'compile.stderr.txt'
# Current staged renderer imports comctl32 TaskDialogIndirect; consumer embeds v6 dependency.
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$buildArgs = @('build','--package-path', $packagePath, '--scratch-path', (Join-Path $packagePath 'scratch'), '-c','release')
if ($plan.hostMode -eq 'renderer') {$buildArgs += @('-Xlinker','/MANIFEST:EMBED','-Xlinker',('"'+$dep+'"'),'-Xlinker','/SUBSYSTEM:WINDOWS','-Xlinker','/ENTRY:mainCRTStartup')}
$p = Start-Process -FilePath (Get-Command swift).Source -ArgumentList $buildArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
Wait-Owned $p 180000
$record = [ordered]@{planSha256=(Get-FileHash -LiteralPath (Join-Path $packagePath 'plan.json')).Hash.ToLowerInvariant();sourceHash=$plan.sourceHash;rendererSha256=$plan.rendererSha256;runtimeSourceCommit=$plan.runtimeSourceCommit;runtimeSourceTreeHash=$plan.runtimeSourceTreeHash;stageSourceCommit=$plan.stageSourceCommit;observedAt=[DateTime]::UtcNow.ToString('o');kind='windows-compile-observation';version='0.1';exitCode=$p.ExitCode;expectation=$plan.compileExpectation;nativeWindowOpened=$false;nativeParity='hold';replays=@()}
if ($p.ExitCode -eq 0 -and $plan.compileExpectation -eq 'success') {
    $binOut = Join-Path $packagePath 'bin-path.stdout.txt'
    $binErr = Join-Path $packagePath 'bin-path.stderr.txt'
    $bp = Start-Process -FilePath (Get-Command swift).Source -ArgumentList @('build','--package-path',$packagePath,'--scratch-path',(Join-Path $packagePath 'scratch'),'-c','release','--show-bin-path') -WindowStyle Hidden -PassThru -RedirectStandardOutput $binOut -RedirectStandardError $binErr
    Wait-Owned $bp 30000
    if ($bp.ExitCode -ne 0) { throw 'Unable to resolve Swift bin path' }
    $bin = (Get-Content -Raw $binOut).Trim()
    if (-not $bin.StartsWith($packagePath + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Bin path escapes factory package' }
    $exe = Join-Path $bin 'FactoryProbe.exe'
    $record.exePath = $exe
    $record.exeSha256 = (Get-FileHash -LiteralPath $exe).Hash.ToLowerInvariant()
    $peBytes=[IO.File]::ReadAllBytes($exe);$peOffset=[BitConverter]::ToInt32($peBytes,60)
    $record.exeSubsystem=[BitConverter]::ToUInt16($peBytes,$peOffset+24+68)
    if($plan.hostMode -eq 'renderer' -and $record.exeSubsystem -ne 2){throw 'Renderer consumer must use GUI subsystem'}
    $record.launchPolicy=if($plan.hostMode -eq 'renderer'){'GUI mainCRTStartup; CREATE_NO_WINDOW; thread CBT activation/focus veto'}else{'headless'}
    if ($plan.hostMode -eq 'headless' -and $plan.executionEligible) {
    for ($i=1; $i -le 20; $i++) {
        $out = Join-Path $packagePath ('layout-{0:00}.json' -f $i)
        $err = Join-Path $packagePath ('layout-{0:00}.stderr.txt' -f $i)
        $run = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
        Wait-Owned $run 10000
        $record.replays += [ordered]@{index=$i;exitCode=$run.ExitCode;path=$out;sha256=(Get-FileHash -LiteralPath $out).Hash.ToLowerInvariant()}
    }
    }
}
Assert-FactoryRuntimeSource $plan $packagePath
$record.compileStdoutHash = (Get-FileHash -LiteralPath $stdout).Hash.ToLowerInvariant()
$record.compileStderrHash = (Get-FileHash -LiteralPath $stderr).Hash.ToLowerInvariant()
$record | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $packagePath 'observation.json')
