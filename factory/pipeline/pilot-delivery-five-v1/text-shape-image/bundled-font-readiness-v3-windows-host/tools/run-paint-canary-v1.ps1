# Root-run bounded Tinos paint canary. Uses packet-local retained-handle helper.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$CompilerPath,
    [Parameter(Mandatory=$true)][string]$FontPath,
    [Parameter(Mandatory=$true)][string]$VcVars64Path,
    [string]$Repo = 'D:\Claude\swiftright',
    [string]$VctipPath,
    [ValidatePattern('^[0-9a-fA-F]{64}$')][string]$VctipSha256,
    [ValidateSet('none','wrong-path','nonmembership','retained-handle')][string]$VctipFaultMode = 'none',
    [ValidateRange(1,10)][int]$Revision = 1,
    [ValidateRange(30,1200)][int]$InnerDeadlineSeconds = 120
)
$ErrorActionPreference='Stop'
$ExpectedRepo='D:\Claude\swiftright'; $Root=[IO.Path]::GetFullPath($Repo)
if($Root -cne $ExpectedRepo){throw 'canonical repository path required'}
$MemoryCap=[UInt64]1073741824; $OutputCap=[Int64]8388608
$Input=Join-Path $Root ('.factory-work\hosts\bundled-font-readiness-v3\windows-host-inputs-r' + $Revision)
$Stage=Join-Path $Root ('.factory-work\hosts\bundled-font-readiness-v3\paint-canary-r' + $Revision)
$Cpp=Join-Path $Input 'paint-canary-v1\FontCustomPaintCanary.cpp'
$Helper=Join-Path $Input 'tools\ProviderOwnedJobProcess.cs'
$FontSha='60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61'
function Require-Regular([string]$Path,[Int64]$Cap){$i=Get-Item -LiteralPath $Path -Force;if($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $i.Length -gt $Cap){throw "bounded regular file required: $Path"};return $i}
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
function Hash-File([string]$Path,[Int64]$Cap){[void](Require-Regular $Path $Cap);return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Invoke-VctipSupervisor([IntPtr]$Job,[uint32]$OwnerPid,[string]$ExpectedPath,[string]$ExpectedHash,[string]$FaultMode) {
    $ids=@([ProviderOwnedJobProcess]::ReadJobProcessIds($Job));$candidate=$null;$candidateHandle=[IntPtr]::Zero
    try {
        foreach($id in $ids){
            if([uint32]$id -eq $OwnerPid){continue}
            $h=[ProviderOwnedJobProcess]::OpenOwnedDescendant([uint32]$id);if($h -eq [IntPtr]::Zero){throw "cannot retain descendant handle: $id"};$keep=$false
            try {
                [bool]$inJob=$false;if(-not [ProviderOwnedJobProcess]::IsInJob($h,$Job,[ref]$inJob) -or -not $inJob){throw "unexpected non-job descendant: $id"}
                $path=[ProviderOwnedJobProcess]::QueryImagePath($h);$leaf=[IO.Path]::GetFileName($path);$start=[ProviderOwnedJobProcess]::QueryStartIdentity($h)
                if($leaf -ine 'vctip.exe'){throw "unexpected job descendant image: $path"};if([string]::IsNullOrWhiteSpace($ExpectedPath) -or [string]::IsNullOrWhiteSpace($ExpectedHash)){throw 'vctip identity pin required'}
                $pathToCompare=$ExpectedPath;if($FaultMode -eq 'wrong-path'){$pathToCompare=$ExpectedPath+'.wrong'};if(-not [String]::Equals($path,$pathToCompare,[StringComparison]::OrdinalIgnoreCase)){throw "vctip image path mismatch: $path"};$hash=Hash-File $path 64MB;if($hash -ine $ExpectedHash.ToLowerInvariant()){throw "vctip image hash mismatch: $hash"};if($FaultMode -eq 'nonmembership'){throw 'vctip nonmembership negative control rejected job member'};if($null -ne $candidate){throw 'ambiguous vctip descendants'};if($FaultMode -eq 'retained-handle'){throw 'retained vctip handle negative control'}
                $candidateHandle=$h;$keep=$true;$candidate=[ordered]@{pid=[uint32]$id;path=$path;sha256=('sha256:'+$hash);originalStart=[uint64]$start;handleRetained=$true;jobMember=$true;forced=$false;exitCode=$null}
            }finally{if(-not $keep){[void][ProviderOwnedJobProcess]::CloseHandle($h)}}
        }
        if($null -eq $candidate){return $null};if(-not [ProviderOwnedJobProcess]::TerminateProcess($candidateHandle,124)){throw 'vctip handle termination failed'};$wait=[ProviderOwnedJobProcess]::WaitForSingleObject($candidateHandle,15000);if($wait -ne 0){throw 'vctip kernel wait failed'};[uint32]$code=259;if(-not [ProviderOwnedJobProcess]::GetExitCodeProcess($candidateHandle,[ref]$code)){throw 'vctip exit certificate unavailable'};$candidate.exitCode=[uint32]$code;$candidate.forced=$true;return $candidate
    }finally{if($candidateHandle -ne [IntPtr]::Zero){[void][ProviderOwnedJobProcess]::CloseHandle($candidateHandle)}}
}
foreach($p in @($Cpp,$Helper,$CompilerPath,$FontPath,$VcVars64Path)){[void](Require-Regular $p 64MB)}
if(Test-Path -LiteralPath $Stage){throw 'refuse overwrite existing canary stage'}
$cppHash=Hash-File $Cpp 16MB; $helperHash=Hash-File $Helper 16MB; $fontHash=Hash-File $FontPath 64MB
if($fontHash -cne $FontSha){throw 'Tinos resource hash mismatch'}
$vsCeipOptOut=Read-VsCeipOptOutDiagnostic
New-Item -ItemType Directory -Path (Join-Path $Stage 'positive') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Stage 'negative') | Out-Null
Add-Type -Path $Helper
function Invoke-Owned([string]$Application,[string]$Arguments,[string]$Cwd,[string]$Stdout,[string]$Stderr,[string]$ReceiptPath,[string]$Kind,[switch]$AllowNonZero){
    $r=[ordered]@{kind=$Kind;application=$Application;argv=$Arguments;cwd=$Cwd;startedAt=[DateTimeOffset]::UtcNow.ToString('o');finishedAt=$null;pid=$null;exitCode=$null;timedOut=$false;outputCapExceeded=$false;ownedExited=$false;originalHandleRetained=$false;streamDrainComplete=$false;streamsSealed=$false;ownedHelperStopped=$null;jobActiveReadable=$false;jobActiveCount=$null;jobActiveCountAfterWait=$null;cleanupJobActive=$null;kernelWait=$null;memoryCapBytes=$MemoryCap;nativeActions=0;stdoutBytes=$null;stdoutSha256=$null;stderrBytes=$null;stderrSha256=$null;error=$null}
    $job=[IntPtr]::Zero;$handle=[IntPtr]::Zero;$thread=[IntPtr]::Zero;$or=[IntPtr]::Zero;$er=[IntPtr]::Zero;$of=$null;$ef=$null;$op=$null;$ep=$null;$ot=$null;$et=$null;$failure=$null
    try{
        $job=[ProviderOwnedJobProcess]::CreateJob();if($job -eq [IntPtr]::Zero -or -not [ProviderOwnedJobProcess]::ConfigureJob($job,$MemoryCap)){throw 'job cap configuration failed'}
        $line=[ProviderOwnedJobProcess]::BuildCommandLine($Application,$Arguments)
        [UInt32]$pidOwned=0;if(-not [ProviderOwnedJobProcess]::CreateSuspended($Application,$line,$Cwd,[ref]$handle,[ref]$thread,[ref]$or,[ref]$er,[ref]$pidOwned)){throw 'suspended process start failed'}
        $r.pid=$pidOwned;$r.originalHandleRetained=($handle -ne [IntPtr]::Zero);$op=New-Object IO.FileStream($or,[IO.FileAccess]::Read,$false);$ep=New-Object IO.FileStream($er,[IO.FileAccess]::Read,$false)
        $of=[IO.File]::Open($Stdout,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$ef=[IO.File]::Open($Stderr,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read);$ot=$op.CopyToAsync($of);$et=$ep.CopyToAsync($ef)
        if(-not [ProviderOwnedJobProcess]::AssignProcessToJobObject($job,$handle)){throw 'job assignment failed'};if([ProviderOwnedJobProcess]::ResumeThread($thread,$handle) -eq [UInt32]::MaxValue){throw 'resume failed'}
        $watch=[Diagnostics.Stopwatch]::StartNew();[UInt32]$wait=258;do{$wait=[ProviderOwnedJobProcess]::WaitForSingleObject($handle,250);$r.kernelWait=$wait;$r.outputCapExceeded=((Get-Item -LiteralPath $Stdout).Length -gt $OutputCap -or (Get-Item -LiteralPath $Stderr).Length -gt $OutputCap);$r.timedOut=($watch.Elapsed.TotalSeconds -ge $InnerDeadlineSeconds);if($r.outputCapExceeded -or $r.timedOut){throw 'canary process cap exceeded'}}while($wait -eq 258)
        [UInt32]$code=259;if($wait -ne 0 -or -not [ProviderOwnedJobProcess]::GetExitCodeProcess($handle,[ref]$code)){throw 'retained exit certificate unavailable'};$r.exitCode=[Int64]$code;$r.ownedExited=$true;$terminalFailure=if($code -ne 0){"owned process exit $code"}else{$null}
        if(-not $ot.Wait(15000) -or -not $et.Wait(15000)){throw 'stream drain timeout'};$ot.GetAwaiter().GetResult();$et.GetAwaiter().GetResult();$r.streamDrainComplete=$true
        $of.Flush();$of.Dispose();$of=$null;$ef.Flush();$ef.Dispose();$ef=$null;$r.streamsSealed=$true;$r.stdoutBytes=(Get-Item -LiteralPath $Stdout).Length;$r.stderrBytes=(Get-Item -LiteralPath $Stderr).Length;$r.stdoutSha256=Hash-File $Stdout $OutputCap;$r.stderrSha256=Hash-File $Stderr $OutputCap
        if($terminalFailure -and -not $AllowNonZero){throw $terminalFailure};if(-not $terminalFailure){$r.ownedHelperStopped=Invoke-VctipSupervisor $job $r.pid $VctipPath $VctipSha256 $VctipFaultMode}
        [UInt32]$active=1;$r.jobActiveReadable=[ProviderOwnedJobProcess]::ReadActiveProcessCount($job,[ref]$active);$r.jobActiveCount=$active;$r.jobActiveCountAfterWait=$active;if(-not $r.jobActiveReadable -or $active -ne 0){throw 'job not quiescent'}
    }catch{$failure=$_.Exception.Message;$r.error=$failure}finally{if($failure){if($job -ne [IntPtr]::Zero){[void][ProviderOwnedJobProcess]::TerminateJobObject($job,124)};if($handle -ne [IntPtr]::Zero){[void][ProviderOwnedJobProcess]::TerminateProcess($handle,124);[void][ProviderOwnedJobProcess]::WaitForSingleObject($handle,15000)}};if($ot){[void]$ot.Wait(5000)};if($et){[void]$et.Wait(5000)};foreach($s in @($of,$ef,$op,$ep)){if($s){$s.Dispose()}};if($job -ne [IntPtr]::Zero){[UInt32]$a=1;$known=[ProviderOwnedJobProcess]::ReadActiveProcessCount($job,[ref]$a);$r.cleanupJobActive=$a;if(-not $known -or $a -ne 0){$r.error=([string]$r.error+' cleanup job not quiescent').Trim()}};foreach($h in @($or,$er,$thread,$handle,$job)){if($h -ne [IntPtr]::Zero){[void][ProviderOwnedJobProcess]::CloseHandle($h)}};$r.finishedAt=[DateTimeOffset]::UtcNow.ToString('o');$r|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $ReceiptPath -Encoding UTF8}
    if($r.error){throw $r.error};return $r
}
$cmdExe=Join-Path $env:WINDIR 'System32\cmd.exe';[void](Require-Regular $cmdExe 4MB);$compileOut=Join-Path $Stage 'compile.stdout.bin';$compileErr=Join-Path $Stage 'compile.stderr.bin';$compileReceipt=Join-Path $Stage 'compile-observation.json';$exe=Join-Path $Stage 'FontCustomPaintCanary.exe';$cmdFile=Join-Path $Stage 'compile-vcvars64.cmd'
$compile='@echo off'+"`r`n"+'set VSCMD_SKIP_SENDTELEMETRY=1'+"`r`n"+'call "'+$VcVars64Path+'"'+"`r`n"+'if errorlevel 1 exit /b %errorlevel%'+"`r`n"+'set VSCMD_SKIP_SENDTELEMETRY=1'+"`r`n"+'"'+$CompilerPath+'" /nologo /std:c++17 /EHsc /O2 /DUNICODE /D_UNICODE /DNOMINMAX "'+$Cpp+'" /Fe:"'+$exe+'" /link dwrite.lib ole32.lib'+"`r`n"+'exit /b %errorlevel%'+"`r`n";Set-Content -LiteralPath $cmdFile -Value $compile -Encoding ASCII -NoNewline
$compileRecord=Invoke-Owned $cmdExe ('/d /s /c "'+$cmdFile+'"') $Stage $compileOut $compileErr $compileReceipt 'factory-bundled-font-canary-compile-v1';if($compileRecord.exitCode -ne 0){throw 'canary compile failed'}
$runs=@();foreach($mode in @('positive','negative')){$out=Join-Path $Stage $mode;$rgba=Join-Path $out 'tinos.rgba.bin';$meta=Join-Path $out 'tinos.metadata.json';$so=Join-Path $out 'stdout.bin';$se=Join-Path $out 'stderr.bin';$rec=Join-Path $out 'paint-receipt.json';$fault=if($mode -eq 'negative'){' --fault-empty-coverage'}else{''};$args='"'+$rgba+'" "'+$meta+'" 18 "'+$FontPath+'" sha256:'+$FontSha+$fault;$allow=($mode -eq 'negative');$run=Invoke-Owned $exe $args $out $so $se $rec ('factory-bundled-font-canary-'+$mode+'-v1') -AllowNonZero:$allow;$runs+=$run}
$positive=Get-Content -LiteralPath (Join-Path $Stage 'positive\tinos.metadata.json') -Raw|ConvertFrom-Json;if($positive.nonEmptyGlyphs -le 0 -or $positive.nonZeroAlphaPixels -le 0 -or $positive.family -cne 'Tinos' -or $positive.postScriptName -cne 'Tinos-Regular'){throw 'positive canary metadata admission failed'}
$negativeReceipt=Get-Content -LiteralPath (Join-Path $Stage 'negative\paint-receipt.json') -Raw|ConvertFrom-Json;if($negativeReceipt.exitCode -eq 0 -or -not (Select-String -LiteralPath (Join-Path $Stage 'negative\stderr.bin') -Pattern 'empty-coverage' -Quiet)){throw 'negative canary admission failed'}
$manifest=[ordered]@{kind='factory-bundled-font-paint-canary-run-v1';revision=$Revision;sourceHash='sha256:'+$cppHash;helperHash='sha256:'+$helperHash;fontSha256='sha256:'+$FontSha;vctipPath=$VctipPath;vctipSha256=$(if($VctipSha256){'sha256:'+$VctipSha256.ToLowerInvariant()}else{$null});vsCeipOptOut=$vsCeipOptOut;compileReceiptSha256='sha256:'+(Hash-File $compileReceipt 4MB);positive=[ordered]@{rgbaSha256='sha256:'+(Hash-File (Join-Path $Stage 'positive\tinos.rgba.bin') 64MB);metadataSha256='sha256:'+(Hash-File (Join-Path $Stage 'positive\tinos.metadata.json') 4MB);receiptSha256='sha256:'+(Hash-File (Join-Path $Stage 'positive\paint-receipt.json') 4MB)};negative=[ordered]@{receiptSha256='sha256:'+(Hash-File (Join-Path $Stage 'negative\paint-receipt.json') 4MB);stderrSha256='sha256:'+(Hash-File (Join-Path $Stage 'negative\stderr.bin') $OutputCap)};memoryCapBytes=$MemoryCap;nativeActions=0;qualification='provider-observation-only'}
$manifest|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $Stage 'paint-canary-manifest.json') -Encoding UTF8
$manifest|ConvertTo-Json -Depth 16
