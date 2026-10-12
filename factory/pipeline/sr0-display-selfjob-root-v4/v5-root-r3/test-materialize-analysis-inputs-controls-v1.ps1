# Source controls for derived frozen-analyzer input materializer; no process is launched.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$item=Get-Item -LiteralPath $SourcePath -Force -ErrorAction Stop;Require (($item.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0) 'materializer reparse source rejected';Require ($item.Length -le 2097152) 'materializer source exceeds bound';$s=[IO.File]::ReadAllText($item.FullName)
$need=@('MaxResultBytes=2097152','MaxStreamBytes=8388608','InputFile $RawResultPath $MaxResultBytes','InputFile $PresentMonStdoutPath $MaxStreamBytes','InputFile $PresentMonStderrPath $MaxStreamBytes','pid_exit run=\S+ pid=\d+ handle=[1-9]\d+','result-workload.adapter.txt','presentmon.console.adapter.txt','rawResultSha256','rawPresentMonStdoutSha256','rawPresentMonStderrSha256','rawPreserved=$true','parityClaim=$false','Write-AtomicJson $OutputPath')
foreach($n in $need){Require ($s.Contains($n)) "materializer guard missing: $n"}
$mut=@{
  'remove-handle-proof'=@{n='pid_exit run=\S+ pid=\d+ handle=[1-9]\d+';r='pid_exit run=\S+ pid=\d+'}
  'result-bound'=@{n='InputFile $RawResultPath $MaxResultBytes';r='InputFile $RawResultPath 9223372036854775807'}
  'stdout-bound'=@{n='InputFile $PresentMonStdoutPath $MaxStreamBytes';r='InputFile $PresentMonStdoutPath 9223372036854775807'}
  'raw-preserved'=@{n='rawPreserved=$true';r='rawPreserved=$false'}
  'parity-claim'=@{n='parityClaim=$false';r='parityClaim=$true'}
}
$cases=[ordered]@{};foreach($k in $mut.Keys){$m=$mut[$k];$changed=$s.Replace($m.n,$m.r);Require ($changed -ne $s) "materializer mutation no effect: $k";$cases[$k]=[ordered]@{status='expected-rejected';changed=$true}}
$out=[ordered]@{kind='sr0-display-analysis-inputs-v1-controls';status='passed';sourcePath=$item.FullName;cases=$cases;nativeActions=0;checkedAt=[DateTimeOffset]::UtcNow.ToString('o')};$full=[IO.Path]::GetFullPath($OutputPath);$parent=Split-Path -Parent $full;if(-not(Test-Path -LiteralPath $parent -PathType Container)){[IO.Directory]::CreateDirectory($parent)|Out-Null};if(Test-Path -LiteralPath $full){throw 'controls output must be fresh'};[IO.File]::WriteAllText($full,($out|ConvertTo-Json -Depth 8)+"`r`n",(New-Object Text.UTF8Encoding($false)));exit 0
