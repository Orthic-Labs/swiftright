# Synthetic fixtures only; actual production guard, no compiler/window/process calls or deletes.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh synthetic output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
$helper=Join-Path $PSScriptRoot '..\..\round1-scroll-host-v1\shared\host-inputs.ps1'
. $helper
function Fixture([string]$name,[string[]]$sources){
 $path=Join-Path $OutputRoot $name
 New-Item -ItemType Directory -Path (Join-Path $path 'Sources\Fixture')|Out-Null
 [IO.File]::WriteAllText((Join-Path $path 'Package.swift'),'// synthetic package')
 foreach($source in $sources){[IO.File]::WriteAllText((Join-Path $path ('Sources\Fixture\'+$source)),'// synthetic source')}
 return $path
}
function Bind([string]$path,[string[]]$names){return @($names|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath (Join-Path $path $_)).Hash.ToLowerInvariant()}})}
function Reject([string]$name,[scriptblock]$body){$caught=$false;try{& $body}catch{$caught=$true};if(-not $caught){throw ('Fault accepted: '+$name)};return @{fault=$name;rejected=$true}}
$normal=Fixture 'normal' @('main.swift')
$bindings=Bind $normal @('Package.swift','Sources/Fixture/main.swift')
Assert-HostCompilerInputs $normal $bindings
$missing=Fixture 'missing' @()
$extra=Fixture 'extra' @('main.swift','extra.swift')
$wrong=Fixture 'equal-count-wrong' @('wrong.swift')
$rows=@()
$rows+=Reject 'missing-source' {Assert-HostCompilerInputs $missing $bindings}
$rows+=Reject 'extra-unbound-source' {Assert-HostCompilerInputs $extra $bindings}
$rows+=Reject 'equal-count-wrong-source' {Assert-HostCompilerInputs $wrong $bindings}
$rows+=Reject 'omitted-binding' {Assert-HostCompilerInputs $normal @($bindings[0])}
$drift=@($bindings|ForEach-Object{@{path=$_.path;sha256=$_.sha256}});$drift[1].sha256='0'*64
$rows+=Reject 'raw-hash-drift' {Assert-HostCompilerInputs $normal $drift}
@{kind='synthetic-production-host-input-guard-controls';synthetic=$true;pass=$true;normalPassed=$true;faults=$rows;helperSha256=(Get-FileHash $helper).Hash.ToLowerInvariant();compilerInvocations=0;nativeWindows=0;filesRetained=$true}|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 (Join-Path $OutputRoot 'controls.json')
