# Optional root-run hidden console child: actual Process/raw CopyToAsync/seal; no renderer/window/compiler.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path $OutputRoot){throw 'Fresh output required'}
. (Join-Path $PSScriptRoot 'stream-seal.ps1')
. (Join-Path $PSScriptRoot 'cleanup.ps1')
New-Item -ItemType Directory $OutputRoot|Out-Null
$exe=Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$info=[Diagnostics.ProcessStartInfo]::new($exe)
$info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
$info.Arguments='-NoProfile -NonInteractive -Command "[Console]::Out.WriteLine(''controlstdout'');[Console]::Error.WriteLine(''controlstderr'')"'
$p=[Diagnostics.Process]::Start($info);$started=$p.StartTime.ToUniversalTime().ToString('o');$streams=@();$primary=$null;$cleanup=$null
try{
 foreach($name in @('stdout','stderr')){
  $file=[IO.File]::Open((Join-Path $OutputRoot ($name+'.bin')),[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::Read)
  $stream=if($name -eq 'stdout'){$p.StandardOutput.BaseStream}else{$p.StandardError.BaseStream}
  $streams+=@{name=$name;file=$file;task=$stream.CopyToAsync($file);sealed=$false}
 }
 if(-not $p.WaitForExit(10000)){throw 'Console raw child deadline'}
 Complete-FactoryRawStreams $streams
 if((Get-Content -Raw (Join-Path $OutputRoot 'stdout.bin')).Trim() -ne 'controlstdout' -or (Get-Content -Raw (Join-Path $OutputRoot 'stderr.bin')).Trim() -ne 'controlstderr'){throw 'Actual child raw bytes wrong'}
 $hashes=@(Get-ChildItem -LiteralPath $OutputRoot -File|ForEach-Object{[ordered]@{path=$_.Name;sha256=(Get-FileHash $_.FullName).Hash.ToLowerInvariant()}})
 if($p.ExitCode -ne 0){throw 'Console child failed'}
}catch{$primary=$_}finally{
 $cleanup=Invoke-FactoryOwnedCleanup $p $exe $started -KnownStartedIdentity
 foreach($stream in $streams){if(-not $stream.sealed){try{$stream.task.Wait(5000)|Out-Null}catch{};try{$stream.file.Flush($true)}catch{};$stream.file.Dispose()}}
}
Assert-FactoryCaptureOutcome $primary $cleanup @()
[ordered]@{pid=$p.Id;path=$exe;startedAt=$started;argv=$info.Arguments;createNoWindow=$true;exitCode=$p.ExitCode;cleanup=$cleanup;files=$hashes}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
