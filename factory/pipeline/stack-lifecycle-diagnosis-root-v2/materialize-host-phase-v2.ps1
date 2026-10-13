param(
 [Parameter(Mandatory=$true)][string]$StderrPath,
 [Parameter(Mandatory=$true)][string]$OutputPath
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';$MaxBytes=262144;$MaxPhases=32
if(-not (Test-Path -LiteralPath $StderrPath -PathType Leaf)){throw "stderr missing: $StderrPath"}
$in=Get-Item -LiteralPath $StderrPath -Force
if(($in.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $in.Length -gt $MaxBytes){throw 'stderr is not bounded regular input'}
$rows=@();$identity=$null
foreach($line in [IO.File]::ReadLines($in.FullName,[Text.Encoding]::UTF8)){
 if([string]::IsNullOrWhiteSpace($line)){continue}
 if($line -notmatch '^FACTORY_STACK_PHASE_V2 (?<body>.+)$'){continue}
 $fields=[ordered]@{};foreach($m in [regex]::Matches($Matches.body,'(?<k>[A-Za-z][A-Za-z0-9]*)=(?<v>[^ ]*)')){$fields[$m.Groups['k'].Value]=$m.Groups['v'].Value}
 foreach($key in @('runId','hostPid','hostStartedUtc','hostPath','sessionId','sourceHash','rendererHash','bridgeHash','runtimeHash','phase','monoMs','qpc','utc')){if(-not $fields.Contains($key)){throw "phase field missing: $key"}}
 $current=($fields.runId,$fields.hostPid,$fields.hostStartedUtc,$fields.hostPath,$fields.sessionId,$fields.sourceHash,$fields.rendererHash,$fields.bridgeHash,$fields.runtimeHash)-join "`n"
 if($null -eq $identity){$identity=$current}else{if($current -cne $identity){throw 'phase identity drift'}}
 if($fields.sourceHash -cnotmatch '^[0-9a-fA-F]{64}$' -or $fields.rendererHash -cnotmatch '^[0-9a-fA-F]{64}$' -or $fields.bridgeHash -cnotmatch '^[0-9a-fA-F]{64}$' -or $fields.runtimeHash -cnotmatch '^[0-9a-fA-F]{64}$'){throw 'phase source hash malformed'}
 $mono=[uint64]$fields.monoMs;$qpc=[uint64]$fields.qpc;if($rows.Count -gt 0 -and ($mono -lt $rows[-1].monoMs -or $qpc -lt $rows[-1].qpc)){throw 'phase clock regression'}
 $rows+=[pscustomobject]@{phase=$fields.phase;monoMs=$mono;qpc=$qpc;utc=$fields.utc;hwnd=if($fields.Contains('hwnd')){[uint64]$fields.hwnd}else{$null}}
 if($rows.Count -gt $MaxPhases){throw 'phase count exceeds bound'}
}
if($rows.Count -eq 0){throw 'no FACTORY_STACK_PHASE_V2 lines'}
$parts=$identity -split "`n",10
$host=[ordered]@{pid=[uint32]$parts[1];startedUtc=$parts[2];path=$parts[3];sessionId=[uint32]$parts[4];sourceHash=$parts[5].ToLowerInvariant();rendererHash=$parts[6].ToLowerInvariant();bridgeHash=$parts[7].ToLowerInvariant();runtimeHash=$parts[8].ToLowerInvariant()}
$out=[ordered]@{kind='factory-stack-host-phase-receipt-v2';runId=$parts[0];host=$host;phases=$rows}
$parent=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($OutputPath));if(-not (Test-Path -LiteralPath $parent -PathType Container)){throw "output directory missing: $parent"}
$tmp="$OutputPath.tmp-$PID";$out|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $tmp -Encoding UTF8;Move-Item -LiteralPath $tmp -Destination $OutputPath -Force
