# Verify dependency roots, move any old package aside (never delete), extract the new package zip.
param([Parameter(Mandatory)][string]$Zip,[Parameter(Mandatory)][string]$Pkg,[Parameter(Mandatory)][string]$Tag,[Parameter(Mandatory)][string]$Stage,[Parameter(Mandatory)][string]$Renderer)
$ErrorActionPreference='Stop'
$w='D:\Claude\swiftright\.factory-work'
foreach($d in "$Stage\STAGE.json","$Stage\packages\SwiftRightHost\Package.swift","$Stage\probes\sr0-s\fresh-runtime\Package.swift","$Stage\packages\SwiftRightBridge\Package.swift",$Renderer){if(-not(Test-Path $d)){throw "missing $d"}}
New-Item -ItemType Directory -Force 'D:\Claude\swiftright\.work'|Out-Null
if(Test-Path $Pkg){Move-Item $Pkg ('D:\Claude\swiftright\.work\'+(Split-Path (Split-Path $Pkg) -Leaf)+'-package-'+$Tag)}
Expand-Archive $Zip $Pkg
