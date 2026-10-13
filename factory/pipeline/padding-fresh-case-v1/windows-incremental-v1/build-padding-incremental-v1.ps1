# Padding incremental Windows builder.  Fresh package only; donor package is read-only.
param(
    [Parameter(Mandatory=$true)][string]$PlanPath,
    [Parameter(Mandatory=$true)][string]$InputRoot,
    [Parameter(Mandatory=$true)][string]$DonorPlanPath,
    [Parameter(Mandatory=$true)][string]$DonorReceiptPath,
    [Parameter(Mandatory=$true)][string]$DonorPackagePath,
    [Parameter(Mandatory=$true)][string]$DonorScratchPath,
    [Parameter(Mandatory=$true)][string]$CompilerPath,
    [Parameter(Mandatory=$true)][string]$RendererPath,
    [Parameter(Mandatory=$true)][string]$JobHelperPath,
    [Parameter(Mandatory=$true)][string]$OutputRoot,
    [switch]$PreflightOnly
)
$ErrorActionPreference = 'Stop'
$MaxJson = [Int64](8MB)
$MaxSource = [Int64](64MB)
$MaxBinary = [Int64](512MB)
$MaxOutput = [Int64](512MB)
$OneGiB = [UInt64]1073741824
$JobMemoryFlag = [UInt32]0x200
$ExpectedJobHelperHash = '112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e'
$DonorPlanSha256 = 'ee83748cd42326e57676e47d8fec777bd8466706ba2c72a01eb9b5b71292de10'

function Assert-Regular([string]$Path, [string]$Label, [Int64]$Limit) {
    $item = Get-Item -LiteralPath $Path -Force
    if($item.PSIsContainer -or $item.LinkType -in @('SymbolicLink','Junction')) { throw "$Label must be regular, non-reparse" }
    if([Int64]$item.Length -gt $Limit) { throw "$Label exceeds $Limit bytes" }
    $item
}
function Read-BytesBounded([string]$Path, [string]$Label, [Int64]$Limit) {
    $item = Assert-Regular $Path $Label $Limit
    $initial = [Int64]$item.Length
    $stream = $null; $memory = [IO.MemoryStream]::new(); $total = [Int64]0
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $buffer = New-Object byte[] (1MB)
        while(($count = $stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $count
            if($total -gt $Limit) { throw "$Label grew beyond bound" }
            $memory.Write($buffer,0,$count)
        }
    } finally { if($stream){$stream.Dispose()} }
    if($total -ne $initial) { throw "$Label changed during read" }
    @{ bytes=$memory.ToArray(); length=$total }
}
function Get-StreamHash([string]$Path, [string]$Label, [Int64]$Limit) {
    $item = Assert-Regular $Path $Label $Limit
    $initial = [Int64]$item.Length
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = $null; $total = [Int64]0
    try {
        $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        $buffer = New-Object byte[] (1MB)
        while(($count = $stream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total += $count
            if($total -gt $Limit) { throw "$Label grew beyond bound" }
            $sha.TransformBlock($buffer,0,$count,$buffer,0) | Out-Null
        }
        $sha.TransformFinalBlock([byte[]]::new(0),0,0) | Out-Null
        $digest = ([BitConverter]::ToString($sha.Hash) -replace '-','').ToLowerInvariant()
    } finally { if($stream){$stream.Dispose()};$sha.Dispose() }
    if($total -ne $initial) { throw "$Label changed during read" }
    @{ sha256=$digest; bytes=$total }
}
function Get-BoundedJson([string]$Path, [string]$Label) {
    $read = Read-BytesBounded $Path $Label $MaxJson
    try { $value = ([Text.Encoding]::UTF8.GetString($read.bytes)).TrimStart([char]0xFEFF) | ConvertFrom-Json }
    catch { throw "$Label invalid JSON: $($_.Exception.Message)" }
    if($null -eq $value) { throw "$Label empty" }
    @{ value=$value; sha256=((Get-Sha256Bytes $read.bytes)); bytes=$read.length }
}
function Get-Sha256Bytes([byte[]]$Bytes) {
    $sha=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Bytes)) -replace '-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Bare([object]$Value, [string]$Label) {
    $text = [string]$Value
    if([string]::IsNullOrWhiteSpace($text)) { throw "$Label hash missing" }
    $text = $text -replace '^sha256:',''
    if($text -notmatch '^[0-9a-fA-F]{64}$') { throw "$Label hash malformed" }
    $text.ToLowerInvariant()
}
function Save-Json([string]$Path, [object]$Value) {
    if(Test-Path -LiteralPath $Path) { throw "fresh output exists: $Path" }
    $parent = Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $text = $Value | ConvertTo-Json -Depth 40
    $bytes = [Text.Encoding]::UTF8.GetBytes($text + "`n")
    if($bytes.Length -gt $MaxJson) { throw "output JSON exceeds bound: $Path" }
    $stream = [IO.File]::Open($Path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush() } finally { $stream.Dispose() }
    @{ sha256=(Get-Sha256Bytes $bytes); bytes=$bytes.Length }
}
function Resolve-Contained([string]$Root, [string]$Relative, [string]$Label) {
    if([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains('\')) { throw "$Label unsafe relative path" }
    if($Relative.Split('/') -contains '..') { throw "$Label escapes root" }
    $path = [IO.Path]::GetFullPath((Join-Path $Root ($Relative -replace '/','\')))
    $rootFull = ([IO.Path]::GetFullPath($Root)).TrimEnd('\') + '\'
    if(-not $path.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)) { throw "$Label escapes root" }
    $path
}
function Assert-RowSet([object]$Rows, [string]$Root, [string]$Label) {
    if($null -eq $Rows) { throw "$Label missing" }
    if(@($Rows).Count -gt 256) { throw "$Label exceeds 256 rows" }
    $seen=@{}; $result=@();$totalBytes=[Int64]0
    foreach($row in @($Rows)) {
        if($null -eq $row.path -or $seen.ContainsKey([string]$row.path)) { throw "$Label duplicate/missing row" }
        $rel=[string]$row.path; $seen[$rel]=$true
        $path=Resolve-Contained $Root $rel "$Label row"
        $actual=Get-StreamHash $path "$Label $rel" $MaxSource
        $totalBytes += [Int64]$actual.bytes
        if($totalBytes -gt [Int64](256MB)) { throw "$Label exceeds 256 MiB total" }
        if($actual.sha256 -ne (Bare $row.sha256 "$Label $rel") -or $actual.bytes -ne [Int64]$row.bytes) { throw "$Label byte/hash drift: $rel" }
        $result += [ordered]@{path=$rel;sha256=$actual.sha256;bytes=$actual.bytes}
    }
    if($result.Count -eq 0) { throw "$Label empty" }
    $result
}
function Require-Same([object]$Left,[object]$Right,[string]$Field) {
    if($null -eq $Left.$Field -or [string]$Left.$Field -cne [string]$Right.$Field) { throw "fresh $Field differs from donor" }
}
function Add-SingleFrontendFlags([string]$ActualArgs) {
    if($ActualArgs -notmatch '(^|\s)-j\s+1(\s|$)') { $ActualArgs += ' -j 1' }
    if($ActualArgs -notmatch '(^|\s)-Xswiftc\s+-num-threads\s+-Xswiftc\s+1(\s|$)') { $ActualArgs += ' -Xswiftc -num-threads -Xswiftc 1' }
    $ActualArgs
}
function Replace-OperationalPaths([string]$ActualArgs,[string]$OldPackage,[string]$OldScratch,[string]$NewPackage,[string]$NewScratch) {
    if(-not $ActualArgs.Contains($OldPackage) -or -not $ActualArgs.Contains($OldScratch)) { throw 'measured donor argv lacks package/scratch paths' }
    (Add-SingleFrontendFlags ($ActualArgs.Replace($OldPackage,$NewPackage).Replace($OldScratch,$NewScratch)))
}
function Assert-Receipt([object]$Receipt,[string]$DonorReceiptHash,[Int64]$DonorReceiptBytes) {
    if([string]$Receipt.kind -cne 'factory-padding-capture-lease-compile-only-owned-handle-v1') { throw 'donor receipt kind drift' }
    if([string]$Receipt.planSha256 -cne $DonorPlanSha256) { throw 'donor receipt plan hash drift' }
    foreach($field in @('sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','compilerHash','rendererSha256','argv','cwd')) { if($null -eq $Receipt.$field){throw "donor receipt $field missing"} }
    if([int]$Receipt.exitCode -ne 0 -or [bool]$Receipt.timedOut -or -not [bool]$Receipt.ownedExited -or -not [bool]$Receipt.streamDrainComplete -or $null -ne $Receipt.error -or $null -ne $Receipt.cleanupError -or [int]$Receipt.kernelWait -ne 0){ throw 'donor terminal receipt not successful' }
    if(@($Receipt.rawStreams).Count -ne 2){ throw 'donor stream receipt incomplete' }
    foreach($stream in @($Receipt.rawStreams)) { if(-not $stream.sealed -or -not $stream.destinationClosed -or [string]$stream.taskStatus -cne 'RanToCompletion' -or [string]$stream.closureTaskStatus -cne 'RanToCompletion'){throw 'donor stream seal drift'} }
    [ordered]@{sha256=$DonorReceiptHash;bytes=$DonorReceiptBytes}
}
function Wait-Compiler([IntPtr]$Handle,[IntPtr]$Job,[string]$Out,[string]$Err,[Int64]$TimeoutMs) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while($true) {
        $wait=[Sr0OwnedJobProcess]::WaitForSingleObject($Handle,250)
        if((Get-Item -LiteralPath $Out -Force).Length -gt $MaxOutput -or (Get-Item -LiteralPath $Err -Force).Length -gt $MaxOutput){throw 'compiler output cap exceeded'}
        if($wait -eq 0){return}
        if($wait -ne 258){throw 'compiler wait failed'}
        if($watch.ElapsedMilliseconds -ge $TimeoutMs){[Sr0OwnedJobProcess]::TerminateJobObject($Job,124)|Out-Null;[Sr0OwnedJobProcess]::WaitForSingleObject($Handle,5000)|Out-Null;throw 'compiler deadline exceeded'}
    }
}

$PlanPath=[IO.Path]::GetFullPath($PlanPath);$InputRoot=[IO.Path]::GetFullPath($InputRoot)
$DonorPlanPath=[IO.Path]::GetFullPath($DonorPlanPath);$DonorReceiptPath=[IO.Path]::GetFullPath($DonorReceiptPath)
$DonorPackagePath=[IO.Path]::GetFullPath($DonorPackagePath);$DonorScratchPath=[IO.Path]::GetFullPath($DonorScratchPath)
$CompilerPath=[IO.Path]::GetFullPath($CompilerPath);$RendererPath=[IO.Path]::GetFullPath($RendererPath);$JobHelperPath=[IO.Path]::GetFullPath($JobHelperPath);$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
$job=[IntPtr]::Zero;$process=[IntPtr]::Zero;$thread=[IntPtr]::Zero;$stdoutRead=[IntPtr]::Zero;$stderrRead=[IntPtr]::Zero
$record=[ordered]@{schema='factory-padding-windows-incremental-build-v1';status='preflight';nativeActions=0;lockActions=0;compilerActions=0;compilerStarted=$false;memoryBudget=[ordered]@{bytes=$OneGiB;jobLimitFlags=$JobMemoryFlag;killOnJobClose=$false;maxFrontendThreads=1}}
$stdoutFile=$null;$stderrFile=$null;$stdoutStream=$null;$stderrStream=$null;$stdoutTask=$null;$stderrTask=$null
$fresh=$null
try {
    foreach($dir in @($InputRoot,$DonorPackagePath)){if(-not (Test-Path -LiteralPath $dir -PathType Container)){throw "package root missing: $dir"}}
    if(Test-Path -LiteralPath $OutputRoot){throw "fresh output collision: $OutputRoot"}
    $freshJson=Get-BoundedJson $PlanPath 'fresh plan';$fresh=$freshJson.value
    $donorPlanJson=Get-BoundedJson $DonorPlanPath 'donor plan';$donor=$donorPlanJson.value
    $receiptJson=Get-BoundedJson $DonorReceiptPath 'donor measured receipt';$receipt=$receiptJson.value
    $donorReceiptProof=Assert-Receipt $receipt $receiptJson.sha256 $receiptJson.bytes
    if($donorPlanJson.sha256 -cne $DonorPlanSha256){throw 'donor plan bytes drift'}
    $request=$fresh.compileRequest
    if($null -eq $request -or [IO.Path]::GetFullPath([string]$request.packagePath) -cne $InputRoot){throw 'fresh input package path drift'}
    if([int]$request.jobs -ne 1 -or [int]$request.maxFrontendThreads -ne 1 -or [string]$request.target -cne 'windows-x86_64' -or [string]$request.configuration -cne 'release'){throw 'single-job fresh request drift'}
    if([bool]$fresh.executionEligible -or [bool]$fresh.frozenTupleBound){throw 'fresh plan must remain pre-capture'}
    if($null -eq $fresh.expectedOutput -or [string]$fresh.expectedOutput -notmatch 'FactoryProbe\.exe$'){throw 'fresh expected output missing'}
    foreach($field in @('sourceHash','runtimeSourceCommit','runtimeSourceTreeHash','compilerHash','rendererSha256')){Require-Same $donor $fresh $field}
    $donorRows=Assert-RowSet $donor.sourceBindings $DonorPackagePath 'donor sourceBindings';$freshRows=Assert-RowSet $fresh.sourceBindings $InputRoot 'fresh sourceBindings'
    if(($donorRows|ConvertTo-Json -Compress) -cne ($freshRows|ConvertTo-Json -Compress)){throw 'fresh source bytes differ from measured donor'}
    if($null -ne $donor.bridgeBindings -or $null -ne $fresh.bridgeBindings){if(($donor.bridgeBindings|ConvertTo-Json -Compress) -cne ($fresh.bridgeBindings|ConvertTo-Json -Compress)){throw 'bridge bindings differ from donor'} }
    $donorPkgPath=[string]$donor.compileRequest.packagePath;$donorScratch=[string]$donor.compileRequest.scratchPath
    if($donorPkgPath -cne $DonorPackagePath -or $donorScratch -cne $DonorScratchPath){throw 'donor operational package/scratch drift'}
    $compiler=Get-StreamHash $CompilerPath 'Swift compiler' $MaxBinary;$renderer=Get-StreamHash $RendererPath 'renderer' $MaxBinary;$helper=Get-StreamHash $JobHelperPath 'original-handle helper' $MaxSource
    if($compiler.sha256 -ne (Bare $donor.compilerHash 'donor compiler') -or $renderer.sha256 -ne (Bare $donor.rendererSha256 'donor renderer') -or $helper.sha256 -ne $ExpectedJobHelperHash){throw 'compiler/renderer/helper bytes drift'}
    $oldExe=Join-Path $DonorScratchPath 'out\Products\Release-windows-x86_64\FactoryProbe.exe';$exe=Get-StreamHash $oldExe 'measured donor executable' $MaxBinary
    if($exe.sha256 -ne '3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10'){throw 'donor executable hash drift'}
    $argsText=Replace-OperationalPaths ([string]$receipt.argv) $DonorPackagePath $DonorScratchPath ([string]$request.packagePath) ([string]$request.scratchPath)
    if($argsText -notmatch '/MANIFEST:EMBED' -or $argsText -notmatch '/SUBSYSTEM:WINDOWS' -or $argsText -notmatch '/ENTRY:mainCRTStartup' -or $argsText -notmatch '(?i)-j 1' -or $argsText -notmatch '(?i)-num-threads\s+-Xswiftc\s+1'){throw 'measured GUI/single-job argv incomplete'}
    $record.planSha256=$freshJson.sha256;$record.donorPlan=$donorPlanJson.sha256;$record.donorReceipt=$donorReceiptProof;$record.sourceHash=$fresh.sourceHash;$record.compilerHash=$compiler.sha256;$record.rendererSha256=$renderer.sha256;$record.existingExecutable=[ordered]@{path=$oldExe;sha256=$exe.sha256;bytes=$exe.bytes};$record.argv=$argsText;$record.argvSource=[ordered]@{path=$DonorReceiptPath;sha256=$receiptJson.sha256;bytes=$receiptJson.bytes;measured=$receipt.argv};$record.packagePath=$request.packagePath;$record.scratchPath=$request.scratchPath
    if($PreflightOnly){$record.status='preflight-passed';$record|ConvertTo-Json -Depth 30;return}
    Add-Type -Path $JobHelperPath
    if(Test-Path -LiteralPath ([IO.Path]::GetFullPath([string]$request.scratchPath))){throw 'fresh scratch already exists'}
    $scratch=[IO.Path]::GetFullPath([string]$request.scratchPath);New-Item -ItemType Directory -Path $scratch|Out-Null
    $outStd=Join-Path $scratch 'compile.stdout.bin';$outErr=Join-Path $scratch 'compile.stderr.bin';$record.compilerStarted=$true;$record.status='running';$record.startedAt=[DateTimeOffset]::UtcNow.ToString('o')
    $job=[Sr0OwnedJobProcess]::CreateJob();if($job -eq [IntPtr]::Zero -or -not [Sr0OwnedJobProcess]::ConfigureJobWithFlags($job,$JobMemoryFlag,$OneGiB)){throw '1GiB job configuration failed'}
    $command=[Sr0OwnedJobProcess]::BuildCommandLine($CompilerPath,$argsText);if(-not [Sr0OwnedJobProcess]::CreateSuspended($CompilerPath,$command,[IO.Path]::GetFullPath([string]$request.packagePath),[ref]$process,[ref]$thread,[ref]$stdoutRead,[ref]$stderrRead,[ref]$record.pid)){throw 'compiler process creation failed'}
    if(-not [Sr0OwnedJobProcess]::AssignProcessToJobObject($job,$process)){throw 'compiler job assignment failed'}
    if([Sr0OwnedJobProcess]::ResumeThread($thread,$process) -eq [UInt32]0xffffffff){throw 'compiler resume failed'}
    $stdoutStream=[IO.FileStream]::new([Microsoft.Win32.SafeHandles.SafeFileHandle]::new($stdoutRead,$true),[IO.FileAccess]::Read,65536,$false);$stdoutRead=[IntPtr]::Zero
    $stderrStream=[IO.FileStream]::new([Microsoft.Win32.SafeHandles.SafeFileHandle]::new($stderrRead,$true),[IO.FileAccess]::Read,65536,$false);$stderrRead=[IntPtr]::Zero
    $stdoutFile=[IO.File]::Open($outStd,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$stderrFile=[IO.File]::Open($outErr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    $stdoutTask=$stdoutStream.CopyToAsync($stdoutFile);$stderrTask=$stderrStream.CopyToAsync($stderrFile);Wait-Compiler $process $job $outStd $outErr 300000
    [uint32]$exit=1;if(-not [Sr0OwnedJobProcess]::GetExitCodeProcess($process,[ref]$exit)){throw 'compiler exit unavailable'};$record.exitCode=$exit
    if(-not $stdoutTask.Wait(30000) -or -not $stderrTask.Wait(30000)){throw 'stream drain deadline exceeded'};$stdoutTask.GetAwaiter().GetResult();$stderrTask.GetAwaiter().GetResult();$stdoutFile.Flush();$stderrFile.Flush()
    [uint32]$active=1;$readable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);$record.jobActiveReadable=$readable;$record.jobActiveCount=$active;if(-not $readable -or $active -ne 0){throw 'job active count not zero'}
    $record.streamsSealed=$true;$record.ownedExited=$true;$record.status=if($exit -eq 0){'compiled-source-bound'}else{'compile-failed'};if($exit -ne 0){throw "compiler exit $exit"}
    $freshExe=[IO.Path]::GetFullPath([string]$fresh.expectedOutput);if(-not (Test-Path -LiteralPath $freshExe)){throw 'fresh expected executable missing'};$newExe=Get-StreamHash $freshExe 'fresh executable' $MaxBinary;$record.freshExecutable=[ordered]@{path=$freshExe;sha256=$newExe.sha256;bytes=$newExe.bytes};$record.finishedAt=[DateTimeOffset]::UtcNow.ToString('o')
} catch { $record.status='hold';$record.error=[string]$_;throw }
finally {
    if($job -ne [IntPtr]::Zero){
        try {
            [uint32]$remaining=1;$readable=[Sr0OwnedJobProcess]::ReadActiveProcessCount($job,[ref]$remaining)
            if($readable -and $remaining -ne 0){[Sr0OwnedJobProcess]::TerminateJobObject($job,124)|Out-Null;[Sr0OwnedJobProcess]::WaitForSingleObject($job,5000)|Out-Null}
            $record.cleanupJobReadable=$readable;$record.cleanupJobActiveCount=$remaining
        } catch {$record.cleanupError=[string]$_}
    }
    foreach($task in @($stdoutTask,$stderrTask)){if($null -ne $task){try{$task.Wait(30000)|Out-Null;$task.GetAwaiter().GetResult()}catch{if($null -eq $record.cleanupError){$record.cleanupError=[string]$_}}}}
    foreach($s in @($stdoutFile,$stderrFile)){if($null -ne $s){try{$s.Flush();$s.Dispose()}catch{}}}
    foreach($s in @($stdoutStream,$stderrStream)){if($null -ne $s){try{$s.Dispose()}catch{}}}
    if($null -ne $fresh -and $null -ne $fresh.compileRequest){
        $receiptScratch=[IO.Path]::GetFullPath([string]$fresh.compileRequest.scratchPath)
        if($null -ne $stdoutFile -and (Test-Path -LiteralPath (Join-Path $receiptScratch 'compile.stdout.bin'))){try{$record.stdoutHash=Get-StreamHash (Join-Path $receiptScratch 'compile.stdout.bin') 'sealed compiler stdout' $MaxOutput}catch{}}
        if($null -ne $stderrFile -and (Test-Path -LiteralPath (Join-Path $receiptScratch 'compile.stderr.bin'))){try{$record.stderrHash=Get-StreamHash (Join-Path $receiptScratch 'compile.stderr.bin') 'sealed compiler stderr' $MaxOutput}catch{}}
    }
    foreach($h in @($thread,$process,$stdoutRead,$stderrRead,$job)){if($h -ne [IntPtr]::Zero){try{[Sr0OwnedJobProcess]::CloseHandle($h)|Out-Null}catch{}}}
    if(-not $PreflightOnly -and $null -ne $OutputRoot -and -not (Test-Path -LiteralPath $OutputRoot)){
        try { New-Item -ItemType Directory -Path $OutputRoot | Out-Null; $saved=Save-Json (Join-Path $OutputRoot 'observation.json') $record; $record.receipt=[ordered]@{path=(Join-Path $OutputRoot 'observation.json');sha256=$saved.sha256;bytes=$saved.bytes} } catch { }
    }
}
$record|ConvertTo-Json -Depth 30
