$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='D:\Claude\swiftright\.factory-work';$Retired=Join-Path $Root 'retired'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'owned compiler/native lane busy'}
if((Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim() -cne 'free'){throw 'desktop lock busy; no stage move'}
New-Item -ItemType Directory -Path $Retired -Force|Out-Null
$Rows=@()
foreach($Name in @('custom-layout-colors')){
 $Source=Join-Path (Join-Path $Root 'hosts') $Name
 $Destination=Join-Path $Retired ($Name+'-primary-paired20-20261012-2110')
 if(Test-Path -LiteralPath $Destination){throw 'fresh retirement destination required'}
 if(Test-Path -LiteralPath $Source){
  $I=Get-Item -LiteralPath $Source
  if(-not $I.PSIsContainer -or ($I.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'owned regular stage required'}
  Move-Item -LiteralPath $Source -Destination $Destination
  if((Test-Path -LiteralPath $Source) -or -not(Test-Path -LiteralPath $Destination)){throw 'same-volume retirement incomplete'}
  $Rows+=@([ordered]@{name=$Name;source=$Source;destination=$Destination;status='moved'})
 }else{$Rows+=@([ordered]@{name=$Name;source=$Source;status='absent'})}
}
[ordered]@{kind='factory-owned-stage-retirement-v1';rows=$Rows;deleteActions=0;desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();activeOwnedStages=@('rectangle');qualified=$false}|ConvertTo-Json -Depth 8
