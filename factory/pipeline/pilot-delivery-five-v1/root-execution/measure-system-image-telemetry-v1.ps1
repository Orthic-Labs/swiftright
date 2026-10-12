$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='C:\Program Files\Microsoft Visual Studio\18\Community\VC\Tools\MSVC\14.51.36231\bin\Hostx64\x64'
$Rows=@();foreach($Name in @('cl.exe','vctip.exe')){
    $P=Join-Path $Root $Name;$I=Get-Item -LiteralPath $P
    if($I.PSIsContainer -or $I.Length -gt 67108864 -or ($I.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded regular tool required'}
    $Rows+=@([ordered]@{name=$Name;path=$I.FullName;bytes=$I.Length;sha256=(Get-FileHash -LiteralPath $P).Hash.ToLowerInvariant()})
}
$Names=@('swift','swiftc','swift-build','swift-frontend','clang','cl','vctip','FactoryProbe')
$Active=@(Get-Process -ErrorAction SilentlyContinue|Where-Object{$Names -contains $_.ProcessName}|Select-Object Id,ProcessName)
if($Active.Count -gt 64){throw 'process inventory exceeds bound'}
[ordered]@{kind='factory-provider-telemetry-tool-measurement-v1';rows=$Rows;activeCompilerOrHost=$Active;desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();nativeActions=0;compilerActions=0;deletionActions=0}|ConvertTo-Json -Depth 8
