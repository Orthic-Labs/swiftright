[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$AdmissionManifestPath,
  [Parameter(Mandatory)][string]$ExpectedTaskName,
  [Parameter(Mandatory)][string]$ExpectedRunRoot,
  [Parameter(Mandatory)][string]$AdmissionHelperPath,
  [Parameter(Mandatory)][ValidatePattern('^[0-9a-fA-F]{64}$')][string]$AdmissionHelperSha256,
  [Parameter(Mandatory)][string]$ControlRoot
)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath($ControlRoot);if(Test-Path -LiteralPath $root){throw 'ControlRoot must be fresh'};[IO.Directory]::CreateDirectory($root)|Out-Null
function Require([bool]$ok,[string]$why){if(-not $ok){throw "admission control rejected: $why"}}
function ReadJson([string]$p){$f=Get-Item -LiteralPath $p -Force;Require (-not $f.PSIsContainer -and ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-eq 0 -and $f.Length -le 2097152) 'bounded regular JSON required';[IO.File]::ReadAllText($f.FullName)|ConvertFrom-Json}
$helper=Get-Item -LiteralPath $AdmissionHelperPath -Force;if($helper.PSIsContainer -or ($helper.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0 -or $helper.Length -gt 2097152){throw 'admission helper bounds'};if((Get-FileHash -LiteralPath $helper.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -cne $AdmissionHelperSha256.ToLowerInvariant()){throw 'admission helper hash'};. $helper
$base=ReadJson $AdmissionManifestPath;if([string]$base.taskName -cne $ExpectedTaskName -or [string]$base.tag -cne $ExpectedTaskName -or [IO.Path]::GetFullPath([string]$base.runRoot) -cne [IO.Path]::GetFullPath($ExpectedRunRoot)){throw 'admitted owner/path does not match expected'};$cases=@();$passed=0
function Case([string]$name,[scriptblock]$mutate,[bool]$expected){$dst=Join-Path $root ($name+'.json');$m=ReadJson $AdmissionManifestPath;&$mutate $m;[IO.File]::WriteAllText($dst,($m|ConvertTo-Json -Depth 24),[Text.UTF8Encoding]::new($false));$ok=$false;$detail='';try{Assert-Sr0R12Admission -Admission (ReadJson $dst) -Requested $base;$ok=$true}catch{$detail=[string]$_.Exception.Message};$pass=($ok -eq $expected);$script:cases+=[ordered]@{name=$name;accepted=$ok;expectedAccepted=$expected;passed=$pass;detail=$detail};if(-not $pass){throw "control failed: $name"};if($pass){$script:passed++}}
Assert-Sr0R12Admission -Admission $base -Requested $base;$cases+=[ordered]@{name='positive-admission';accepted=$true;expectedAccepted=$true;passed=$true};$passed++
Case 'wrong-task' {$args[0].taskName='foreign-task'} $false
Case 'wrong-tag' {$args[0].tag='foreign-task'} $false
Case 'wrong-owner-runroot' {$args[0].runRoot=(Join-Path $root 'foreign-run')} $false
Case 'wrong-deadline' {$args[0].deadlineSeconds=901} $false
Case 'wrong-memory' {$args[0].aggregateJobMemoryLimitBytes=536870912} $false
Case 'wrong-flags' {$args[0].aggregateLimitFlags=256} $false
Case 'wrong-noactivate' {$args[0].noActivate=$false} $false
Case 'wrong-binary-hash' {$args[0].workloadExeSha256='0'*64} $false
Case 'missing-runroot' {$args[0].runRoot=$null} $false
$receipt=[ordered]@{kind='sr0-display-selfjob-r12-admission-controls';status='passed-source-controls';cases=$cases.Count;passed=$passed;nativeActions=0;lockActions=0;qualificationClaim=$false;controlRoot=$root};$receipt|ConvertTo-Json -Depth 12;exit 0
