[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$DrainHelperPath,
  [Parameter(Mandatory)][string]$DrainHelperSha256,
  [Parameter(Mandatory)][string]$OutputPath,
  [Parameter(Mandatory)][string]$WorkRoot
)
$ErrorActionPreference='Stop'
$sha='^[0-9a-fA-F]{64}$';if($DrainHelperSha256 -notmatch $sha){throw 'drain helper SHA-256 required'}
$helper=[IO.Path]::GetFullPath($DrainHelperPath);if(-not(Test-Path -LiteralPath $helper -PathType Leaf)){throw 'drain helper missing'};$item=Get-Item -LiteralPath $helper -Force;if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $item.Length -gt 131072){throw 'drain helper bounds/reparse gate failed'};if((Get-FileHash -LiteralPath $helper -Algorithm SHA256).Hash.ToLowerInvariant() -cne $DrainHelperSha256.ToLowerInvariant()){throw 'drain helper hash mismatch'};. $helper
if(-not(Test-Path -LiteralPath $WorkRoot)){[IO.Directory]::CreateDirectory($WorkRoot)|Out-Null}
$powershell=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Quote-DrainArg([string]$Value){if($Value -notmatch '[\s"]'){return $Value};return '"'+$Value.Replace('"','\"')+'"'}
function Invoke-DrainCase([string]$Name,[string]$FilePath,[string[]]$Arguments,[int]$ExpectedExit,[int]$TimeoutSeconds,[bool]$ExpectTerminal,[bool]$ExpectInheritedPipeDelay){
  $psi=[Diagnostics.ProcessStartInfo]::new();$psi.FileName=$FilePath;$psi.Arguments=(($Arguments|ForEach-Object{Quote-DrainArg ([string]$_)}) -join ' ');$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
  $p=[Diagnostics.Process]::Start($psi);$out=$p.StandardOutput.ReadToEndAsync();$err=$p.StandardError.ReadToEndAsync();$proof=$null;$cleanupError=$null
  try {$proof=Complete-WorkloadDrainV1 -Process $p -StdoutTask $out -StderrTask $err -TimeoutSeconds $TimeoutSeconds
    if($ExpectTerminal -and (-not $proof.processWaitCompleted -or -not $proof.processTerminal -or -not $proof.streamsDrained)){throw "drain case failed: $Name"}
    if(-not $ExpectTerminal -and ($proof.processTerminal -or $proof.processWaitCompleted)){throw "nonterminal control unexpectedly completed: $Name"}
    if($proof.elapsedMilliseconds -gt ($TimeoutSeconds*1000+1000) -or -not $proof.totalBudgetBounded){throw "drain total budget exceeded: $Name"}
    if($ExpectTerminal -and [int]$p.ExitCode -ne $ExpectedExit){throw "drain exit mismatch: $Name"}
  } finally {
    if(-not $p.HasExited){try{$p.Kill()}catch{$cleanupError=$_.Exception.Message};try{[void]$p.WaitForExit(5000)}catch{$cleanupError=if($cleanupError){$cleanupError}else{$_.Exception.Message}}}
  }
  $stdoutText=if($out.IsCompleted){$out.GetAwaiter().GetResult()}else{'<stdout-drain-timeout>'};$stderrText=if($err.IsCompleted){$err.GetAwaiter().GetResult()}else{'<stderr-drain-timeout>'}
  [ordered]@{name=$Name;exit=if($p.HasExited){[int]$p.ExitCode}else{$null};expectedExit=$ExpectedExit;expectTerminal=$ExpectTerminal;expectInheritedPipeDelay=$ExpectInheritedPipeDelay;proof=$proof;stdout=$stdoutText;stderr=$stderrText;cleanupError=$cleanupError}
}
$cases=@()
$cases+=Invoke-DrainCase 'exit-zero' $powershell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command','Write-Output drain-zero; exit 0') 0 15 $true $false
$cases+=Invoke-DrainCase 'exit-natural-nonzero' $powershell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command','Write-Output drain-nonzero; exit 17') 17 15 $true $false
$cases+=Invoke-DrainCase 'delayed-output' $powershell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command','Start-Sleep -Milliseconds 750; [Console]::Out.Write("drain-delayed"); [Console]::Out.Flush(); exit 0') 0 15 $true $false
# cmd inherits redirected stdout/stderr while its nested PowerShell writer stays alive after cmd starts it.
$inheritCommand='start "" /b powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Start-Sleep -Seconds 2; Write-Output inherited-delay"; Write-Output parent-exit; exit 0'
$cases+=Invoke-DrainCase 'inherited-pipe-delay' (Join-Path $env:SystemRoot 'System32\cmd.exe') @('/d','/s','/c',$inheritCommand) 0 15 $true $true
$cases+=Invoke-DrainCase 'nonterminal-timeout' $powershell @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-Command','Start-Sleep -Seconds 20') -1 1 $false $false
$out=[ordered]@{kind='sr0-display-workload-drain-controls-v1';status='passed-source-controls';helperSha256=$DrainHelperSha256.ToLowerInvariant();cases=$cases;controls=@('exit-zero','exit-natural-nonzero','delayed-output','inherited-pipe-delay','nonterminal-timeout');nativeQualificationClaim=$false}
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath));if(-not(Test-Path -LiteralPath $parent)){[IO.Directory]::CreateDirectory($parent)|Out-Null};if(Test-Path -LiteralPath $OutputPath){throw 'controls output must be fresh'};[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutputPath),($out|ConvertTo-Json -Depth 16)+"`r`n",(New-Object Text.UTF8Encoding($false)));exit 0
