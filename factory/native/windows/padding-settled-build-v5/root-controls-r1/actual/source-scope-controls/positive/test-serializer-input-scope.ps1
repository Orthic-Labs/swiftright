# Executes exact production guard function only; file fixtures, zero process/compiler/window launches.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputRoot){throw 'Fresh scope-control output required'}
New-Item -ItemType Directory -Path $OutputRoot|Out-Null
$driver=Join-Path $PSScriptRoot 'run-serializer-control.ps1'
$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($driver,[ref]$tokens,[ref]$parseErrors)
if(@($parseErrors).Count){throw 'Driver parse errors'}
$functions=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-Inputs'},$true))
if($functions.Count -ne 1){throw 'Exact one production guard required'}
$guard=$functions[0].Extent.Text
. ([scriptblock]::Create($guard))
$planPath=Join-Path $PSScriptRoot 'package\plan.json'
$script:serializerPayloadPath=Join-Path $PSScriptRoot 'package\Sources\FactoryProbe\MetricsPayload.swift'
$control=Join-Path $PSScriptRoot 'serializer-control\main.swift'
$streamHelper=Join-Path $PSScriptRoot 'stream-seal.ps1'
$cleanupHelper=Join-Path $PSScriptRoot 'cleanup-decision.ps1'
$swiftc=Join-Path $OutputRoot 'synthetic-tool-bytes.bin'
[IO.File]::WriteAllText($swiftc,'synthetic fixture; never executed')
$SwiftcSha256=(Get-FileHash $swiftc).Hash.ToLowerInvariant()
$expectedPayload=$script:serializerPayloadPath
$rows=@()
# Meaningful original fault: nested caller dynamically shadows source with pipe-like stream object.
$pipe=[IO.MemoryStream]::new()
try {
 & { $source=$pipe; $serializerPayloadPath=$pipe; Assert-Inputs }
 $rows+=@{mode='pipe-source-shadow';passed=$true;synthetic=$true}
 & { $source='System.IO.FileStream'; $serializerPayloadPath='wrong-local-path'; Assert-Inputs }
 $rows+=@{mode='string-source-shadow';passed=$true;synthetic=$true}
 foreach($mode in @('wrong-script-payload','wrong-script-tool-hash')){
  $script:serializerPayloadPath=$expectedPayload
  $savedToolHash=$SwiftcSha256
  if($mode -ceq 'wrong-script-payload'){$script:serializerPayloadPath=$control}else{$SwiftcSha256='0'*64}
  $caught=$false;$reason=''
  try { & { $source=$pipe; Assert-Inputs } } catch {$caught=$true;$reason=[string]$_}
  $expectedReason=if($mode -ceq 'wrong-script-payload'){'Serializer source/plan drift'}else{'Measured actual swiftc bytes required'}
  if(-not $caught -or $reason -cne $expectedReason){throw ('Wrong production scope fault disposition '+$mode+': '+$reason)}
  $rows+=@{mode=$mode;rejected=$true;reason=$reason;synthetic=$true}
  $SwiftcSha256=$savedToolHash
 }
} finally {$pipe.Dispose();$script:serializerPayloadPath=$expectedPayload}
[ordered]@{kind='production-serializer-input-scope-controls';driverSha256=(Get-FileHash $driver).Hash.ToLowerInvariant();guardSource=$guard;guardSha256=([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($guard))).Replace('-','').ToLowerInvariant());synthetic=$true;compilerActions=0;nativeActions=0;controls=$rows}|ConvertTo-Json -Depth 12|Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutputRoot 'controls.json')
