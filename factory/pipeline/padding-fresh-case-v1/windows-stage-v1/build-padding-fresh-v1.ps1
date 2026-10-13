# Fresh Padding Windows compiler entry. Compiler-only: no GUI, native window, or lock action.
param(
    [Parameter(Mandatory=$true)][string]$Package,
    [Parameter(Mandatory=$true)][string]$CompilerPath,
    [Parameter(Mandatory=$true)][string]$JobHelperPath,
    [Parameter(Mandatory=$true)][string]$ReceiptPath,
    [switch]$PreflightOnly
)
$ErrorActionPreference = 'Stop'
$MaxJson = 8MB
$MaxInput = 256MB
$MaxOutput = 512MB
$OneGiB = [UInt64]1073741824
$JobMemoryFlag = [UInt32]0x200
$ExpectedJobHelperHash = '112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e'

function Assert-Regular([string]$Path, [string]$Label, [Int64]$Limit) {
    $item = Get-Item -LiteralPath $Path -Force
    if(-not $item.PSIsContainer -and $item.LinkType -notin @('SymbolicLink','Junction')) {
        if($item.Length -le $Limit){ return $item }
    }
    throw "$Label must be regular, non-reparse, <= $Limit bytes"
}
function Get-StreamHash([string]$Path, [string]$Label, [Int64]$Limit) {
    $item = Assert-Regular $Path $Label $Limit
    $initial = [Int64]$item.Length
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = $null
    $total = [Int64]0
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $buffer = New-Object byte[] (1MB)
        while(($count = $stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $sha.TransformBlock($buffer,0,$count,$buffer,0) | Out-Null
            $total += $count
            if($total -gt $Limit){ throw "$Label grew beyond bound" }
        }
        $sha.TransformFinalBlock([byte[]]::new(0),0,0) | Out-Null
        $digest = ([BitConverter]::ToString($sha.Hash) -replace '-','').ToLowerInvariant()
    } finally { if($stream){$stream.Dispose()};$sha.Dispose() }
    if($total -ne $initial){ throw "$Label changed during read" }
    @{ sha256=$digest; bytes=$total }
}
function Get-BoundedJson([string]$Path, [string]$Label) {
    $item = Assert-Regular $Path $Label $MaxJson
    $stream = $null
    $memory = [IO.MemoryStream]::new()
    $total = [Int64]0
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $buffer = New-Object byte[] (1MB)
        while(($count = $stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $count
            if($total -gt $MaxJson){ throw "$Label grew beyond bound" }
            $memory.Write($buffer,0,$count)
        }
    } finally { if($stream){$stream.Dispose()} }
    if($total -ne [Int64]$item.Length){ throw "$Label changed during read" }
    $raw = $memory.ToArray();$memory.Dispose()
    $text = [Text.Encoding]::UTF8.GetString($raw).TrimStart([char]0xFEFF)
    $text | ConvertFrom-Json
}
function Save-Receipt($Value) {
    if(Test-Path -LiteralPath $ReceiptPath){ throw "receipt already exists: $ReceiptPath" }
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8 -NoNewline
}
function Assert-HashRef($Ref, [string]$Path, [string]$Label, [Int64]$Limit) {
    if(-not $Ref -or $Ref.path -ne $Path){ throw "$Label path drift" }
    $actual = Get-StreamHash (Join-Path $Package $Path) $Label $Limit
    if($actual.bytes -ne [Int64]$Ref.bytes -or $actual.sha256 -ne ($Ref.sha256 -replace '^sha256:','').ToLowerInvariant()){ throw "$Label bytes/hash drift" }
}
function Wait-BoundedCompiler([IntPtr]$Handle,[string]$StdoutPath,[string]$StderrPath,[Int64]$TimeoutMs) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true) {
        $wait=[Sr0OwnedJobProcess]::WaitForSingleObject($Handle,250)
        if((Get-Item -LiteralPath $StdoutPath -Force).Length -gt $MaxOutput -or (Get-Item -LiteralPath $StderrPath -Force).Length -gt $MaxOutput) {
            throw 'compiler output cap exceeded'
        }
        if($wait -eq 0){ return 0 }
        if($wait -ne 258){ throw 'compiler wait failed' }
        if($watch.ElapsedMilliseconds -ge $TimeoutMs){
            [Sr0OwnedJobProcess]::TerminateProcess($Handle,124)|Out-Null
            [Sr0OwnedJobProcess]::WaitForSingleObject($Handle,5000)|Out-Null
            throw 'compiler deadline exceeded'
        }
    }
}

$Package = [IO.Path]::GetFullPath($Package)
$CompilerPath = [IO.Path]::GetFullPath($CompilerPath)
$JobHelperPath = [IO.Path]::GetFullPath($JobHelperPath)
$ReceiptPath = [IO.Path]::GetFullPath($ReceiptPath)
$planPath = Join-Path $Package 'plan.json'
$plan = Get-BoundedJson $planPath 'fresh plan'
$request = $plan.compileRequest
if(-not $request){ throw 'fresh compile request missing' }
if([IO.Path]::GetFullPath($request.packagePath) -cne $Package){ throw 'package path drift' }
if([string]$request.jobHelperPath -cne $JobHelperPath -or [string]$plan.memoryBudget.helperPath -cne $JobHelperPath){ throw 'job helper path drift' }
if($request.configuration -cne 'release' -or $request.target -cne 'windows-x86_64' -or $request.jobs -ne 1 -or $request.maxFrontendThreads -ne 1){ throw 'single-job compiler contract drift' }
if($plan.executionEligible -ne $false -or $plan.frozenTupleBound -ne $false){ throw 'compile stage must remain pre-capture' }
$compiler = Get-StreamHash $CompilerPath 'Swift compiler' 256MB
if($request.compilerPath -cne $CompilerPath -or $compiler.sha256 -ne (($plan.compilerHash -replace '^sha256:','').ToLowerInvariant())){ throw 'compiler bytes/path drift' }
$renderer = Get-StreamHash $plan.rendererPath 'renderer' 256MB
if($renderer.sha256 -ne (($plan.rendererSha256 -replace '^sha256:','').ToLowerInvariant())){ throw 'renderer bytes drift' }
$helper = Get-StreamHash $JobHelperPath 'original-handle job helper' 64MB
if($helper.sha256 -cne $ExpectedJobHelperHash){ throw 'approved original-handle helper required' }
if($null -eq $plan.freshInputRefs){ throw 'fresh input refs missing' }
foreach($entry in $plan.freshInputRefs.PSObject.Properties){
    if($null -eq $entry.Value){ throw "fresh input $($entry.Name) missing" }
    Assert-HashRef $entry.Value $entry.Value.path "fresh input $($entry.Name)" $MaxJson
}
$witness = Get-StreamHash (Join-Path $Package 'Sources\FactoryProbe\Witness.swift') 'fresh witness' 8MB
if($witness.sha256 -ne (($plan.sourceHash -replace '^sha256:','').ToLowerInvariant())){ throw 'fresh witness/source drift' }
$scratch = [IO.Path]::GetFullPath($request.scratchPath)
if(Test-Path -LiteralPath $scratch){ throw "fresh scratch exists: $scratch" }
$record = [ordered]@{
    schema='factory-padding-fresh-windows-compile-v1'; status='preflight-passed'; planSha256=(Get-StreamHash $planPath 'fresh plan' $MaxJson).sha256
    packagePath=$Package; compilerPath=$CompilerPath; compilerHash=$compiler.sha256; rendererSha256=$renderer.sha256
    sourceHash=$witness.sha256; runtimeSourceCommit=$plan.runtimeSourceCommit; expectedOutput=$plan.expectedOutput
    memoryBudget=[ordered]@{bytes=$OneGiB;jobLimitFlags=$JobMemoryFlag;killOnJobClose=$false;helperSha256=$helper.sha256}
    compilerStarted=$false; nativeActions=0; lockActions=0; compilerActions=0; jobActiveReadable=$false; jobActiveCount=$null; streamsSealed=$false
}
if($PreflightOnly){ $record.status='preflight-passed'; Save-Receipt $record; $record | ConvertTo-Json -Depth 16; return }

Add-Type -Path $JobHelperPath
$job=[IntPtr]::Zero;$process=[IntPtr]::Zero;$thread=[IntPtr]::Zero;$stdoutRead=[IntPtr]::Zero;$stderrRead=[IntPtr]::Zero
$stdoutStream=$null;$stderrStream=$null;$stdoutFile=$null;$stderrFile=$null;$stdoutTask=$null;$stderrTask=$null
try {
    New-Item -ItemType Directory -Path $scratch | Out-Null
    $job=[Sr0OwnedJobProcess]::CreateJob()
    if($job -eq [IntPtr]::Zero -or -not [Sr0OwnedJobProcess]::ConfigureJobWithFlags($job,$JobMemoryFlag,$OneGiB)){ throw '1GiB compiler job configuration failed' }
    $argsText='build --package-path "'+$Package+'" --scratch-path "'+$scratch+'" -c release -j 1 -Xswiftc -num-threads -Xswiftc 1 -Xlinker /MANIFEST:EMBED -Xlinker "/MANIFESTDEPENDENCY:type=''win32'' name=''Microsoft.Windows.Common-Controls'' version=''6.0.0.0'' processorArchitecture=''*'' publicKeyToken=''6595b64144ccf1df'' language=''*''" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
    $command=[Sr0OwnedJobProcess]::BuildCommandLine($CompilerPath,$argsText)
    if(-not [Sr0OwnedJobProcess]::CreateSuspended($CompilerPath,$command,$Package,[ref]$process,[ref]$thread,[ref]$stdoutRead,[ref]$stderrRead,[ref]$record.pid)){ throw 'compiler process creation failed' }
    if(-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$process)){ throw 'compiler job assignment failed' }
    if([Sr0OwnedJobProcess]::ResumeThread($thread,$process) -eq [UInt32]0xffffffff){ throw 'compiler resume failed' }
    $record.compilerStarted=$true;$record.status='running';$record.startedAt=[DateTimeOffset]::UtcNow.ToString('o')
    $stdoutStream=[IO.FileStream]::new([Microsoft.Win32.SafeHandles.SafeFileHandle]::new($stdoutRead,$true),[IO.FileAccess]::Read,65536,$false);$stdoutRead=[IntPtr]::Zero
    $stderrStream=[IO.FileStream]::new([Microsoft.Win32.SafeHandles.SafeFileHandle]::new($stderrRead,$true),[IO.FileAccess]::Read,65536,$false);$stderrRead=[IntPtr]::Zero
    $stdoutFile=[IO.File]::Open((Join-Path $scratch 'compile.stdout.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $stderrFile=[IO.File]::Open((Join-Path $scratch 'compile.stderr.bin'),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $stdoutTask=$stdoutStream.CopyToAsync($stdoutFile);$stderrTask=$stderrStream.CopyToAsync($stderrFile)
    Wait-BoundedCompiler $process (Join-Path $scratch 'compile.stdout.bin') (Join-Path $scratch 'compile.stderr.bin') 300000 | Out-Null
    $record.exitCode=[UInt32]0;$null=[Sr0OwnedJobProcess]::GetExitCodeProcess($process,[ref]$record.exitCode)
    if(-not $stdoutTask.Wait(30000) -or -not $stderrTask.Wait(30000)){ throw 'compiler output drain incomplete' }
    $stdoutTask.GetAwaiter().GetResult();$stderrTask.GetAwaiter().GetResult()
    if((Get-Item -LiteralPath (Join-Path $scratch 'compile.stdout.bin') -Force).Length -gt $MaxOutput -or (Get-Item -LiteralPath (Join-Path $scratch 'compile.stderr.bin') -Force).Length -gt $MaxOutput){ throw 'compiler output cap exceeded after drain' }
    [uint32]$active=1;$record.jobActiveReadable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);$record.jobActiveCount=$active
    if(-not $record.jobActiveReadable -or $active -ne 0){ throw 'compiler job not quiescent' }
    $stdoutFile.Flush();$stderrFile.Flush();$record.streamsSealed=$true
    $record.status=if($record.exitCode -eq 0){'compiled-source-bound'}else{'compile-failed'}
    if($record.exitCode -ne 0){ throw "compiler exit code $($record.exitCode)" }
    if(-not (Test-Path -LiteralPath $plan.expectedOutput)){ throw 'expected FactoryProbe.exe missing' }
    $exe=Get-StreamHash $plan.expectedOutput 'fresh FactoryProbe.exe' 256MB
    $record.exeSha256=$exe.sha256;$record.exeBytes=$exe.bytes
    $record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o')
} catch { $record.status='compile-hold';$record.error=[string]$_;throw }
finally {
    foreach($stream in @($stdoutFile,$stderrFile,$stdoutStream,$stderrStream)){ if($null -ne $stream){try{$stream.Dispose()}catch{}} }
    if($thread -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($thread)|Out-Null}
    if($process -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($process)|Out-Null}
    if($stdoutRead -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($stdoutRead)|Out-Null}
    if($stderrRead -ne [IntPtr]::Zero){[Sr0OwnedJobProcess]::CloseHandle($stderrRead)|Out-Null}
    if($job -ne [IntPtr]::Zero){
        [uint32]$remaining=1;$readable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$remaining)
        $record.cleanupJobActive=$remaining;$record.cleanupJobReadable=$readable
        if(-not $readable -or $remaining -ne 0){$record.cleanupError='compiler job quiescence not certified'}
        [Sr0OwnedJobProcess]::CloseHandle($job)|Out-Null
    }
    if(-not (Test-Path -LiteralPath $ReceiptPath)){ Save-Receipt $record }
}
$record | ConvertTo-Json -Depth 16
