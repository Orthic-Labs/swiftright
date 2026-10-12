$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if(@(Get-Process swift,swiftc,swift-build,swift-frontend,clang,cl,vctip,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'owned build/native lane busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop lane busy'}
$Base='D:\Claude\swiftright\.factory-work\hosts\rounded-stroke-centered\captures'
$Retired='D:\Claude\swiftright\.factory-work\retired\rounded-native-retries-20261012-r1'
if(Test-Path -LiteralPath $Retired){throw 'fresh retirement root required'}
New-Item -ItemType Directory -Path $Retired -Force|Out-Null
$Rows=@();foreach($Name in @('count1-r7','count1-r8','count1-r9','count1-r10','count1-r12')){
    $Src=Join-Path $Base $Name;$Dst=Join-Path $Retired $Name
    $Exists=Test-Path -LiteralPath $Src
    if($Exists){$I=Get-Item -LiteralPath $Src;if(-not $I.PSIsContainer -or ($I.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'owned regular directory required'};Move-Item -LiteralPath $Src -Destination $Dst}
    $Rows+=@([ordered]@{source=$Src;destination=$Dst;existed=$Exists;moved=($Exists -and (Test-Path -LiteralPath $Dst) -and -not(Test-Path -LiteralPath $Src))})
}
[ordered]@{kind='factory-quiescent-stage-retirement-v1';rows=$Rows;desktopLock='free';deletionActions=0;compilerActions=0;nativeActions=0}|ConvertTo-Json -Depth 8
