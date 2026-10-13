# Root-run guarded DirectWrite producer. This script never installs fonts, opens a
# desktop/window, mutates remote hosts, or deletes evidence.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CompilerPath,
    [Parameter(Mandatory=$true)][string]$FontPath,
    [Parameter(Mandatory=$true)][string]$VcVars64Path,
    [string]$Repo = 'D:\Claude\swiftright',
    [string]$VctipPath,
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$VctipSha256,
    [ValidateRange(1,512)][double]$FontEmSize = 32.0,
    [ValidateSet('none','empty-coverage','vctip-wrong-path','vctip-nonmembership','vctip-retained-handle')][string]$FaultMode = 'none',
    [ValidateRange(1,10)][int]$Revision = 1,
    [ValidateRange(30,1200)][int]$InnerDeadlineSeconds = 120,
    [switch]$PreflightOnly
)
$ErrorActionPreference = 'Stop'
$ExpectedRepo = 'D:\Claude\swiftright'
$MemoryCap = [UInt64]1073741824
$OutputCap = [Int64]8388608
$RgbaCap = [Int64]67108864
$Root = [IO.Path]::GetFullPath($Repo)
if($Root -cne $ExpectedRepo){ throw 'canonical repository path required' }
$P = $PSScriptRoot
$Stage = Join-Path $Root ('.factory-work\hosts\system-star-fill\provider-raster-r' + $Revision)
$Cpp = Join-Path $P 'GlyphRasterProducer.cpp'
$Helper = Join-Path $P 'ProviderOwnedJobProcess.cs'
function Require-Regular([string]$Path,[Int64]$Cap) {
    $i = Get-Item -LiteralPath $Path -Force
    if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $i.Length -gt $Cap){ throw "bounded regular file required: $Path" }
    return $i
}
function Read-VsCeipOptOutDiagnostic {
    # Microsoft documents registry-backed VSCEIP state. Read only diagnostic;
    # compiler admission never mutates or gates on host-wide telemetry policy.
    $paths = @(
        'HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\SQM',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\VSCommon\17.0\SQM',
        'HKLM:\SOFTWARE\Microsoft\VSCommon\17.0\SQM'
    )
    $seen = @()
    foreach($path in $paths) {
        if(Test-Path -LiteralPath $path) {
            try {
                $value = (Get-ItemProperty -LiteralPath $path -Name OptIn -ErrorAction Stop).OptIn
                $seen += [ordered]@{path=$path;OptIn=[int]$value}
            } catch { }
        }
    }
    return $seen
}
function Hash-File([string]$Path,[Int64]$Cap) {
    [void](Require-Regular $Path $Cap)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Q([string]$Value) { if($null -eq $Value){throw 'null argument'}; return '"' + $Value + '"' }
function Invoke-VctipSupervisor([IntPtr]$Job,[uint32]$OwnerPid,[string]$ExpectedPath,[string]$ExpectedHash,[string]$FaultMode) {
    $ids = @([ProviderOwnedJobProcess]::ReadJobProcessIds($Job))
    $candidate = $null; $candidateHandle = [IntPtr]::Zero
    try {
        foreach($id in $ids) {
            if([uint32]$id -eq $OwnerPid){ continue }
            $h = [ProviderOwnedJobProcess]::OpenOwnedDescendant([uint32]$id)
            if($h -eq [IntPtr]::Zero){ throw "cannot retain descendant handle: $id" }
            $keep = $false
            try {
                [bool]$inJob = $false
                if(-not [ProviderOwnedJobProcess]::IsInJob($h,$Job,[ref]$inJob) -or -not $inJob){ throw "unexpected non-job descendant: $id" }
                $path = [ProviderOwnedJobProcess]::QueryImagePath($h)
                $leaf = [IO.Path]::GetFileName($path)
                $start = [ProviderOwnedJobProcess]::QueryStartIdentity($h)
                if($leaf -ine 'vctip.exe'){ throw "unexpected job descendant image: $path" }
                if([string]::IsNullOrWhiteSpace($ExpectedPath) -or [string]::IsNullOrWhiteSpace($ExpectedHash)){ throw 'vctip identity pin required' }
                $pathToCompare = $ExpectedPath
                if($FaultMode -eq 'vctip-wrong-path'){ $pathToCompare = $ExpectedPath + '.wrong' }
                if(-not [String]::Equals($path,$pathToCompare,[StringComparison]::OrdinalIgnoreCase)){ throw "vctip image path mismatch: $path" }
                $hash = Hash-File $path 64MB
                if($hash -ine $ExpectedHash.ToLowerInvariant()){ throw "vctip image hash mismatch: $hash" }
                if($FaultMode -eq 'vctip-nonmembership'){ throw 'vctip nonmembership negative control rejected job member' }
                if($null -ne $candidate){ throw 'ambiguous vctip descendants' }
                if($FaultMode -eq 'vctip-retained-handle'){ throw 'retained vctip handle negative control' }
                $candidateHandle=$h; $keep=$true
                $candidate=[ordered]@{pid=[uint32]$id;path=$path;sha256=('sha256:' + $hash);originalStart=[uint64]$start;handleRetained=$true;jobMember=$true;forced=$false;exitCode=$null}
            } finally { if(-not $keep){ [void][ProviderOwnedJobProcess]::CloseHandle($h) } }
        }
        if($null -eq $candidate){ return $null }
        if(-not [ProviderOwnedJobProcess]::TerminateProcess($candidateHandle,124)){ throw 'vctip handle termination failed' }
        $wait=[ProviderOwnedJobProcess]::WaitForSingleObject($candidateHandle,15000)
        if($wait -ne 0){ throw 'vctip kernel wait failed' }
        [uint32]$code=259
        if(-not [ProviderOwnedJobProcess]::GetExitCodeProcess($candidateHandle,[ref]$code)){ throw 'vctip exit certificate unavailable' }
        $candidate.exitCode=[uint32]$code; $candidate.forced=$true
        return $candidate
    } finally { if($candidateHandle -ne [IntPtr]::Zero){ [void][ProviderOwnedJobProcess]::CloseHandle($candidateHandle) } }
}
if(-not (Test-Path -LiteralPath $Cpp -PathType Leaf) -or -not (Test-Path -LiteralPath $Helper -PathType Leaf)){ throw 'owned producer sources missing' }
$compiler = Require-Regular $CompilerPath (64MB)
$font = Require-Regular $FontPath (64MB)
$vcvars = Require-Regular $VcVars64Path (16MB)
$cppHash = Hash-File $Cpp (16MB)
$helperHash = Hash-File $Helper (16MB)
$fontHash = Hash-File $FontPath (64MB)
$vcvarsHash = Hash-File $VcVars64Path (16MB)
$fontBytes = $font.Length
$vsCeipOptOut = Read-VsCeipOptOutDiagnostic
if(Test-Path -LiteralPath $Stage){ throw 'refuse overwrite existing provider-raster stage' }
$CompileArgs = '/nologo /std:c++17 /EHsc /O2 /DUNICODE /D_UNICODE ' + (Q $Cpp) + ' /Fe:' + (Q (Join-Path $Stage 'compiler\GlyphRasterProducer.exe')) + ' /link dwrite.lib ole32.lib'
$preflight = [ordered]@{
    kind='factory-system-image-provider-raster-preflight-v1'; status='source-only'; identity='star.fill'; provider='Segoe Fluent Icons'; glyph='E735'
    repo=$Root; outputRoot=$Stage; compilerPath=$CompilerPath; compilerSha256=('sha256:' + (Hash-File $CompilerPath (64MB))); vctipPath=$VctipPath; vctipSha256=$(if($VctipSha256){'sha256:' + $VctipSha256.ToLowerInvariant()}else{$null})
    sourceHash=('sha256:' + $cppHash); helperHash=('sha256:' + $helperHash); fontPath=$FontPath; fontBytes=$fontBytes; fontSha256=('sha256:' + $fontHash); vcVars64Path=$VcVars64Path; vcVars64Sha256=('sha256:' + $vcvarsHash); vsCeipOptOut=$vsCeipOptOut
    compileArgv=$CompileArgs; compilerEnvironment='cmd.exe /d /s /c VSCMD_SKIP_SENDTELEMETRY=1; call measured vcvars64.bat; reapply VSCMD_SKIP_SENDTELEMETRY=1; cl.exe'; memoryCapBytes=$MemoryCap; outputCapBytes=$OutputCap; nativeActions=0; fontInstallation=$false
}
if($PreflightOnly){ $preflight | ConvertTo-Json -Depth 8; return }
New-Item -ItemType Directory -Path (Join-Path $Stage 'compiler') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Stage 'producer') | Out-Null
$compileCommandFile=Join-Path $Stage 'compile-vcvars64.cmd'
$compileCommand='@echo off' + "`r`n" + 'set VSCMD_SKIP_SENDTELEMETRY=1' + "`r`n" + 'call "' + $VcVars64Path + '"' + "`r`n" + 'if errorlevel 1 exit /b %errorlevel%' + "`r`n" + 'set VSCMD_SKIP_SENDTELEMETRY=1' + "`r`n" + '"' + $CompilerPath + '" ' + $CompileArgs + "`r`n" + 'exit /b %errorlevel%' + "`r`n"
Set-Content -LiteralPath $compileCommandFile -Value $compileCommand -Encoding ASCII -NoNewline
$cmdExe=Join-Path $env:WINDIR 'System32\cmd.exe'; [void](Require-Regular $cmdExe (4MB))
Add-Type -Path $Helper
function Invoke-Owned([string]$Application,[string]$Arguments,[string]$Cwd,[string]$Stdout,[string]$Stderr,[string]$ReceiptPath,[string]$Kind) {
    $r = [ordered]@{ kind=$Kind; application=$Application; argv=$Arguments; cwd=$Cwd; startedAt=[DateTimeOffset]::UtcNow.ToString('o'); finishedAt=$null; pid=$null; exitCode=$null; timedOut=$false; outputCapExceeded=$false; ownedExited=$false; originalHandleRetained=$false; streamDrainComplete=$false; streamsSealed=$false; ownedHelperStopped=$null; jobActiveReadable=$false; jobActiveCount=$null; jobActiveCountAfterWait=$null; jobProcessIds=@(); jobProcessNames=@(); cleanupJobActive=$null; kernelWait=$null; memoryCapBytes=$MemoryCap; jobFlags=8704; nativeActions=0; stdoutBytes=$null; stdoutSha256=$null; stderrBytes=$null; stderrSha256=$null; error=$null }
    $job=[IntPtr]::Zero; $handle=[IntPtr]::Zero; $thread=[IntPtr]::Zero; $or=[IntPtr]::Zero; $er=[IntPtr]::Zero; $pidOwned=[UInt32]0; $op=$null; $ep=$null; $of=$null; $ef=$null; $ot=$null; $et=$null; $failure=$null
    try {
        $job=[ProviderOwnedJobProcess]::CreateJob()
        if($job -eq [IntPtr]::Zero -or -not [ProviderOwnedJobProcess]::ConfigureJob($job,$MemoryCap)){ throw 'job cap configuration failed' }
        $line=[ProviderOwnedJobProcess]::BuildCommandLine($Application,$Arguments)
        if(-not [ProviderOwnedJobProcess]::CreateSuspended($Application,$line,$Cwd,[ref]$handle,[ref]$thread,[ref]$or,[ref]$er,[ref]$pidOwned)){ throw 'suspended process start failed' }
        $r.pid=$pidOwned; $r.originalHandleRetained=($handle -ne [IntPtr]::Zero)
        $op=New-Object IO.FileStream($or,[IO.FileAccess]::Read,$false); $ep=New-Object IO.FileStream($er,[IO.FileAccess]::Read,$false)
        $of=[IO.File]::Open($Stdout,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read); $ef=[IO.File]::Open($Stderr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
        $ot=$op.CopyToAsync($of); $et=$ep.CopyToAsync($ef)
        if(-not [ProviderOwnedJobProcess]::AssignProcessToJobObject($job,$handle)){ throw 'job assignment failed' }
        if([ProviderOwnedJobProcess]::ResumeThread($thread,$handle) -eq [UInt32]::MaxValue){ throw 'resume failed' }
        $watch=[Diagnostics.Stopwatch]::StartNew(); [UInt32]$wait=258
        do {
            $wait=[ProviderOwnedJobProcess]::WaitForSingleObject($handle,250); $r.kernelWait=$wait
            $r.outputCapExceeded=((Get-Item -LiteralPath $Stdout).Length -gt $OutputCap -or (Get-Item -LiteralPath $Stderr).Length -gt $OutputCap)
            $r.timedOut=($watch.Elapsed.TotalSeconds -ge $InnerDeadlineSeconds)
            if($r.outputCapExceeded -or $r.timedOut){ throw 'producer process cap exceeded' }
        } while($wait -eq 258)
        [UInt32]$code=259
        if($wait -ne 0 -or -not [ProviderOwnedJobProcess]::GetExitCodeProcess($handle,[ref]$code)){ throw 'retained exit certificate unavailable' }
        $r.exitCode=[Int64]$code; $r.ownedExited=$true
        $terminalFailure = if($code -ne 0){ "owned process exit $code" } else { $null }
        if(-not $ot.Wait(15000) -or -not $et.Wait(15000)){ throw 'stream drain timeout' }
        $ot.GetAwaiter().GetResult(); $et.GetAwaiter().GetResult(); $r.streamDrainComplete=$true
        $of.Flush(); $of.Dispose(); $of=$null; $ef.Flush(); $ef.Dispose(); $ef=$null; $r.streamsSealed=$true
        $r.stdoutBytes=(Get-Item -LiteralPath $Stdout).Length; $r.stderrBytes=(Get-Item -LiteralPath $Stderr).Length; $r.stdoutSha256=Hash-File $Stdout $OutputCap; $r.stderrSha256=Hash-File $Stderr $OutputCap
        if($terminalFailure){ throw $terminalFailure }
        $r.ownedHelperStopped=Invoke-VctipSupervisor $job $r.pid $VctipPath $VctipSha256 $FaultMode
        [UInt32]$active=1; $r.jobActiveReadable=[ProviderOwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active); $r.jobActiveCount=$active
        $r.jobActiveCountAfterWait=$active
        if(-not $r.jobActiveReadable -or $active -ne 0){ throw 'job not quiescent' }
    } catch { $failure=$_.Exception.Message; $r.error=$failure }
    finally {
        if($failure){ if($job -ne [IntPtr]::Zero){ [void][ProviderOwnedJobProcess]::TerminateJobObject($job,124) }; if($handle -ne [IntPtr]::Zero){ [void][ProviderOwnedJobProcess]::TerminateProcess($handle,124); [void][ProviderOwnedJobProcess]::WaitForSingleObject($handle,15000) } }
        if($ot){ [void]$ot.Wait(5000) }; if($et){ [void]$et.Wait(5000) }
        foreach($s in @($of,$ef,$op,$ep)){ if($s){ $s.Dispose() } }
        if($job -ne [IntPtr]::Zero){ [UInt32]$a=1; $known=[ProviderOwnedJobProcess]::ReadActiveProcessCount($job,[ref]$a); $r.cleanupJobActive=$a; if(-not $known -or $a -ne 0){ $r.error=([string]$r.error + ' cleanup job not quiescent').Trim() } }
        foreach($h in @($or,$er,$thread,$handle,$job)){ if($h -ne [IntPtr]::Zero){ [void][ProviderOwnedJobProcess]::CloseHandle($h) } }
        $r.finishedAt=[DateTimeOffset]::UtcNow.ToString('o'); $r | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $ReceiptPath -Encoding UTF8
    }
    if($r.error){ throw $r.error }
    return $r
}
$compileOut=Join-Path $Stage 'compile.stdout.bin'; $compileErr=Join-Path $Stage 'compile.stderr.bin'; $compileReceipt=Join-Path $Stage 'compile-observation.json'; $producerExe=Join-Path $Stage 'compiler\GlyphRasterProducer.exe'
$compileRecord=Invoke-Owned $cmdExe ('/d /s /c ' + (Q $compileCommandFile)) $Stage $compileOut $compileErr $compileReceipt 'factory-system-image-provider-compile-v1'
if($compileRecord.exitCode -ne 0){ throw 'producer compile failed' }; $producerExeHash=Hash-File $producerExe (64MB); $producerExeBytes=(Get-Item -LiteralPath $producerExe).Length
$rgba=Join-Path $Stage 'producer\star-fill.rgba.bin'; $metadata=Join-Path $Stage 'producer\provider-metadata.json'; $producerOut=Join-Path $Stage 'producer.stdout.bin'; $producerErr=Join-Path $Stage 'producer.stderr.bin'; $producerReceipt=Join-Path $Stage 'producer-observation.json'
$producerArgs=(Q $rgba) + ' ' + (Q $metadata) + ' ' + ($FontEmSize.ToString('0.######',[Globalization.CultureInfo]::InvariantCulture)) + ' ' + (Q $FontPath) + ' ' + (Q $fontHash)
if($FaultMode -ceq 'empty-coverage'){ $producerArgs += ' --fault-empty-coverage' }
$producerRecord=Invoke-Owned $producerExe $producerArgs $Stage $producerOut $producerErr $producerReceipt 'factory-system-image-provider-producer-v1'
if($producerRecord.exitCode -ne 0){ throw 'provider raster process failed' }
$bytes=[IO.File]::ReadAllBytes($rgba); if($bytes.Length -gt $RgbaCap){ throw 'RGBA cap exceeded' }
$meta=Get-Content -LiteralPath $metadata -Raw | ConvertFrom-Json
$meta | Add-Member -NotePropertyName processPid -NotePropertyValue ([Int64]$producerRecord.pid) -Force
if($meta.identity -cne 'star.fill' -or $meta.provider -cne 'Segoe Fluent Icons' -or $meta.unicode -cne 'E735' -or $meta.fontFileMatched -ne $true -or [int64]$meta.processPid -ne [int64]$producerRecord.pid -or [int]$meta.rgbaBytes -ne $bytes.Length -or [int64]$meta.nonZeroAlphaPixels -le 0){ throw 'provider metadata identity/coverage/byte mismatch' }
$width=[int]$meta.texture.width; $height=[int]$meta.texture.height; if($width -le 0 -or $height -le 0 -or ($width * $height * 4) -ne $bytes.Length){ throw 'texture dimensions mismatch' }
$rgbaHash=Hash-File $rgba $RgbaCap; $meta | Add-Member -NotePropertyName rgbaSha256 -NotePropertyValue ('sha256:' + $rgbaHash) -Force; $meta | Add-Member -NotePropertyName status -NotePropertyValue 'provider-raster-ready-pending-root-native-render' -Force; $meta | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $metadata -Encoding UTF8
$providerVersion=[string]$meta.postScriptName; if([string]::IsNullOrWhiteSpace($providerVersion)){ throw 'DirectWrite provider version missing' }; $map=[ordered]@{schema='factory-system-image-provider-map-v1'; mappingVersion='segoe-fluent-icons-star-fill-v1'; identity='star.fill'; provider='Segoe Fluent Icons'; providerVersion=$providerVersion; glyph='E735'; foregroundSemantic='system.yellow'; glyphIndex=[int]$meta.glyphIndex; width=$width; height=$height; color=[ordered]@{r=255;g=204;b=0;alpha='directwrite'}; rgbaBytes=$bytes.Length; rgbaSha256=('sha256:' + $rgbaHash); rgbaBase64=[Convert]::ToBase64String($bytes); status='provider-raster-ready'; licenseStatus='unverified'}
$mapPath=Join-Path $Stage 'FactorySystemImageAssets.json'; $map | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $mapPath -Encoding UTF8; if((Get-Item -LiteralPath $mapPath).Length -gt $RgbaCap){ throw 'mapping JSON cap exceeded' }
$manifest=[ordered]@{kind='factory-system-image-provider-raster-manifest-v1'; identity='star.fill'; provider='Segoe Fluent Icons'; glyph='E735'; fontPath=$FontPath; fontBytes=$fontBytes; fontSha256=('sha256:' + $fontHash); vcVars64Path=$VcVars64Path; vcVars64Sha256=('sha256:' + $vcvarsHash); vctipPath=$VctipPath; vctipSha256=$(if($VctipSha256){'sha256:' + $VctipSha256.ToLowerInvariant()}else{$null}); vsCeipOptOut=$vsCeipOptOut; producerProcessPid=[Int64]$producerRecord.pid; sourceHash=('sha256:' + $cppHash); helperHash=('sha256:' + $helperHash); compilerHash=('sha256:' + (Hash-File $CompilerPath (64MB))); producerExe=[ordered]@{path='compiler/GlyphRasterProducer.exe';bytes=$producerExeBytes;sha256=('sha256:' + $producerExeHash)}; rgba=[ordered]@{path='producer/star-fill.rgba.bin';bytes=$bytes.Length;sha256=('sha256:' + $rgbaHash)}; metadata=[ordered]@{path='producer/provider-metadata.json';bytes=(Get-Item -LiteralPath $metadata).Length;sha256=('sha256:' + (Hash-File $metadata 4MB))}; map=[ordered]@{path='FactorySystemImageAssets.json';bytes=(Get-Item -LiteralPath $mapPath).Length;sha256=('sha256:' + (Hash-File $mapPath 96MB))}; compileReceipt=[ordered]@{path='compile-observation.json';sha256=('sha256:' + (Hash-File $compileReceipt 4MB))}; producerReceipt=[ordered]@{path='producer-observation.json';sha256=('sha256:' + (Hash-File $producerReceipt 4MB))}; memoryCapBytes=$MemoryCap; nativeActions=0; fontInstallation=$false; qualification='held-until-root-native-render'}
$manifestPath=Join-Path $Stage 'provider-raster-manifest.json'; $manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
[ordered]@{status='provider-raster-produced';stage=$Stage;identity='star.fill';glyphIndex=[int]$meta.glyphIndex;rgbaBytes=$bytes.Length;rgbaSha256=('sha256:' + $rgbaHash);fontSha256=('sha256:' + $fontHash);nativeActions=0;qualification='held-until-root-native-render'} | ConvertTo-Json -Depth 8
