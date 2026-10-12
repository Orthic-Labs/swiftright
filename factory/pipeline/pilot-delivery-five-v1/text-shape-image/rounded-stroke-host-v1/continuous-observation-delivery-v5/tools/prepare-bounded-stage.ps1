# Root-owned stage preparation; source-only packet, no compiler/native launch.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Repo,
  [Parameter(Mandatory=$true)][ValidateSet('rounded-stroke-observation-v5')][string]$Host,
  [switch]$PreflightOnly
)
$ErrorActionPreference='Stop'
$Repo=[IO.Path]::GetFullPath($Repo)
if($Repo -cne 'D:\Claude\swiftright'){throw 'Exact workspace root required'}
$packet=Join-Path $Repo 'factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\continuous-observation-delivery-v5'
$source=Join-Path $packet 'package'
$stage=Join-Path $Repo ('.factory-work\hosts\'+$Host+'\package')
$runtime=Join-Path $Repo '.factory-work\runtime-stage\runtime'
$bridge=Join-Path $Repo '.factory-work\inputs\SwiftRightBridge'
$renderer=Join-Path $Repo '.factory-work\inputs\renderer\swiftright_render.dll'
foreach($p in @($source,$runtime,$bridge,$renderer)){if(-not (Test-Path -LiteralPath $p)){throw "Required current staged input missing: $p"}}
if(Test-Path -LiteralPath $stage){throw 'Fresh host stage required; refusing overwrite'}
$files=@(Get-ChildItem -LiteralPath $source -Recurse -File)
if($files.Count -gt 256){throw 'Source file bound exceeded'}
$total=($files|Measure-Object Length -Sum).Sum
if($total -gt 268435456){throw 'Source byte bound exceeded'}
$pkg=Get-Content -LiteralPath (Join-Path $source 'Package.swift') -Raw
$main=Get-Content -LiteralPath (Join-Path $source 'Sources\FactoryProbe\main.swift') -Raw
if($pkg -notlike '*D:\\Claude\\swiftright\\.factory-work\\runtime-stage\\runtime*' -or $pkg -notlike '*D:\\Claude\\swiftright\\.factory-work\\inputs\\SwiftRightBridge*'){throw 'Package dependency namespace drift'}
if($main -notlike '*D:\\Claude\\swiftright\\.factory-work\\inputs\\renderer\\swiftright_render.dll*'){throw 'Renderer namespace drift'}
if($PreflightOnly){[ordered]@{kind='pilot-delivery-bounded-stage-preflight-v1';host=$Host;source=$source;destination=$stage;runtime=$runtime;bridge=$bridge;renderer=$renderer;fileCount=$files.Count;sourceBytes=$total;copyStarted=$false;nativeActions=0;qualification='source-only'}|ConvertTo-Json -Depth 8;return}
New-Item -ItemType Directory -Force -Path (Split-Path $stage)|Out-Null
Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
[ordered]@{kind='pilot-delivery-bounded-stage-v1';host=$Host;source=$source;destination=$stage;runtime=$runtime;bridge=$bridge;renderer=$renderer;fileCount=$files.Count;sourceBytes=$total;compilerStarted=$false;nativeActions=0;qualification='source-staged-pending-root-compile'}|ConvertTo-Json -Depth 8
