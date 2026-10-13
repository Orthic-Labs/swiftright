$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$src='D:\Claude\swiftright\.factory-work\hosts\custom-layout-colors'
$dst='D:\Claude\swiftright\.factory-work\retired\custom-layout-colors-direct-v6-observed-20261013-0120'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop lock busy'}
if(Test-Path -LiteralPath $dst){throw 'retirement destination already exists'}
$receipt=Join-Path $src 'final-r1\observation.json'
if((Get-FileHash -LiteralPath $receipt).Hash.ToLowerInvariant() -cne '1e68b743a8766279e8c610137aa99257c717bbd5c3a85508eb4761532cd82d4b'){throw 'prior final receipt drift'}
$r=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
if(-not $r.exePath.StartsWith($src+'\package\') -or (Get-FileHash -LiteralPath $r.exePath).Hash.ToLowerInvariant() -cne 'b6c4d088252032ffd21180c9691e4673abbcb2cdfa3401d1fabdb449cbf3d176'){throw 'prior EXE drift'}
$i=Get-Item -LiteralPath $src -Force
if(-not $i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'regular owned stage required'}
New-Item -ItemType Directory -Path (Split-Path -Parent $dst) -Force|Out-Null
Move-Item -LiteralPath $src -Destination $dst
if((Test-Path -LiteralPath $src) -or -not(Test-Path -LiteralPath $dst)){throw 'same-volume retirement incomplete'}
[ordered]@{kind='factory-terminal-custom-v6-retirement';source=$src;destination=$dst;deleteActions=0;priorReceiptSha256='1e68b743a8766279e8c610137aa99257c717bbd5c3a85508eb4761532cd82d4b';priorExeSha256='b6c4d088252032ffd21180c9691e4673abbcb2cdfa3401d1fabdb449cbf3d176';desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim()}|ConvertTo-Json -Depth 5
