# Verify dependency roots, move any old package aside (never delete), extract the new package zip.
param([Parameter(Mandatory)][string]$Zip,[Parameter(Mandatory)][string]$Pkg,[Parameter(Mandatory)][string]$Tag)
$ErrorActionPreference='Stop'
$w='D:\Claude\swiftright\.factory-work'
foreach($d in "$w\runtime-stage\runtime","$w\inputs\SwiftRightBridge","$w\inputs\renderer\swiftright_render.dll"){if(-not(Test-Path $d)){throw "missing $d"}}
New-Item -ItemType Directory -Force 'D:\Claude\swiftright\.work'|Out-Null
if(Test-Path $Pkg){Move-Item $Pkg ('D:\Claude\swiftright\.work\'+(Split-Path (Split-Path $Pkg) -Leaf)+'-package-'+$Tag)}
Expand-Archive $Zip $Pkg
