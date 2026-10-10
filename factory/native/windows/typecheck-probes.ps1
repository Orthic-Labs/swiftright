# Typecheck unchanged generated witnesses against staged compiled module; no executable/window run.
param([Parameter(Mandatory=$true)][string]$SourceDir)
$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\factory\native\windows\'
$src=[IO.Path]::GetFullPath($SourceDir)
if (-not $src.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'Sources outside factory' }
$module='D:\Claude\sr0-r09\src\scratch\out\Intermediates.noindex\fresh-runtime.build\Release-windows-x86_64\SwiftRightRuntime-t.build\Objects-normal\x86_64\Modules'
$records=@()
foreach ($file in Get-ChildItem -LiteralPath $src -Filter '*.swift' -File) {
    $out=Join-Path $src ($file.BaseName+'.typecheck.stdout.txt')
    $err=Join-Path $src ($file.BaseName+'.typecheck.stderr.txt')
    $hash=(Get-FileHash -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    $p=Start-Process -FilePath (Get-Command swiftc).Source -ArgumentList @('-typecheck','-I',$module,$file.FullName) -WindowStyle Hidden -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $timeout=-not $p.WaitForExit(30000)
    if($timeout){& taskkill /PID $p.Id /T /F | Out-Null}
    $records += [ordered]@{source=$file.Name;sourceHash=$hash;exitCode=if($timeout){$null}else{$p.ExitCode};timeout=$timeout;stderrHash=(Get-FileHash -LiteralPath $err).Hash.ToLowerInvariant();stdoutHash=(Get-FileHash -LiteralPath $out).Hash.ToLowerInvariant();nativeWindowOpened=$false;nativeReplayPerformed=$false}
}
[ordered]@{kind='windows-typecheck-observation';version='0.1';observedAt=[DateTimeOffset]::UtcNow.ToString('o');modulePath=$module;moduleSha256=(Get-FileHash -LiteralPath (Join-Path $module 'SwiftRightRuntime.swiftmodule')).Hash.ToLowerInvariant();sources=$records} | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 (Join-Path $src 'typecheck-observation.json')
