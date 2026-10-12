param([Parameter(Mandatory=$true)][string]$Package,[Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference='Stop'
$source=Join-Path $Package 'Resources\Tinos-Regular.ttf'
$dest=Join-Path (Split-Path -Parent $Executable) 'Tinos-Regular.ttf'
if(-not (Test-Path -LiteralPath $source)){throw 'Tinos resource missing'}
if(Test-Path -LiteralPath $dest){throw 'Fresh executable resource destination required'}
$h=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
if($h -ne '60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61'){throw 'Tinos source hash mismatch'}
Copy-Item -LiteralPath $source -Destination $dest
$dh=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
if($dh -ne $h){throw 'Tinos staged hash mismatch'}
[ordered]@{kind='tinos-resource-stage-v1';source=$source;destination=$dest;sha256=('sha256:'+ $dh);bytes=(Get-Item -LiteralPath $dest).Length;status='staged'}|ConvertTo-Json -Compress
