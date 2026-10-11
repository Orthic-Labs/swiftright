# Pure production predicate replay; no child/renderer/compiler/window actions.
param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
$driver=Join-Path $PSScriptRoot 'capture-repeat.ps1'
$raw=[IO.File]::ReadAllText($driver);$tokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($driver,[ref]$tokens,[ref]$parseErrors)
if(@($parseErrors).Count){throw 'Runner AST errors'}
$assignments=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$validHost'},$true))
$guards=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst] -and $n.Extent.Text -ceq "if(-not `$validHost){throw 'Owned host output failed original validity predicate'}"},$true))
if($assignments.Count -ne 1 -or $guards.Count -ne 1){throw 'Exact production validity assignment/guard required'}
if($guards[0].Extent.StartOffset -le $assignments[0].Extent.EndOffset -or $raw.Substring($assignments[0].Extent.EndOffset,$guards[0].Extent.StartOffset-$assignments[0].Extent.EndOffset).Trim().Length){throw 'Guard must immediately follow original computed predicate'}
$production=[scriptblock]::Create($assignments[0].Extent.Text+"`n"+$guards[0].Extent.Text)
$rows=@();$fixtures=Get-Content -Raw (Join-Path $PSScriptRoot 'fixtures.json')|ConvertFrom-Json
foreach($f in $fixtures){
 $path=Join-Path $PSScriptRoot ('fixtures\'+$f.name+'.stdout.bin')
 if((Get-FileHash $path).Hash.ToLowerInvariant() -cne $f.sha256){throw 'Fixture raw byte drift'}
 $hostOutput=[IO.File]::ReadAllText($path);$p=[pscustomobject]@{ExitCode=0};$caught=$false;$reason=''
 if($f.errorToken -and -not $hostOutput.Contains($f.errorToken)){throw 'Actual fault token absent'}
 try{. $production}catch{$caught=$true;$reason=$_.Exception.Message}
 if($f.expected -ceq 'accept') {if($caught -or -not $validHost){throw 'Actual baseline rejected'}}
 else {if(-not $caught -or $reason -cne 'Owned host output failed original validity predicate'){throw 'Actual fault did not reject at production validity guard'}}
 $rows+=@{name=$f.name;rawSha256=$f.sha256;exitCode=0;accepted=(-not $caught);reason=$reason}
}
$hostOutput='FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto FACTORY_RENDERER_READY FACTORY_COMMIT';$p=[pscustomobject]@{ExitCode=1};$caught=$false
try{. $production}catch{if($_.Exception.Message -cne 'Owned host output failed original validity predicate'){throw};$caught=$true}
if(-not $caught){throw 'Nonzero exit accepted'}
$rows+=@{name='nonzero-exit';accepted=$false;exitCode=1}
[ordered]@{kind='production-host-validity-raw-controls';driverSha256=(Get-FileHash $driver).Hash.ToLowerInvariant();productionSource=$production.ToString();controls=$rows;nativeActions=0;compilerActions=0;passed=$true}|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 $OutputPath
