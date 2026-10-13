# Install fresh Padding source package from explicit manifest; source-only, no compiler/native/lock action.
param([Parameter(Mandatory=$true)][string]$SourceInputsPath,[Parameter(Mandatory=$true)][string]$StageRoot,[Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][string]$PlanPath)
$ErrorActionPreference='Stop'
function H([string]$p,[long]$lim=67108864){$i=Get-Item -LiteralPath $p -Force;if($i.PSIsContainer -or $i.LinkType -or $i.Length -gt $lim){throw "bounded regular required: $p"};(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function J([string]$p){if((Get-Item -LiteralPath $p -Force).Length -gt 2097152){throw 'JSON bound'};Get-Content -Raw -LiteralPath $p|ConvertFrom-Json}
if(Test-Path -LiteralPath $StageRoot){throw 'fresh stage required'}
$src=[IO.Path]::GetFullPath($SourceInputsPath);$d=J $src;if($d.kind -ne 'factory-padding-source-inputs-v2' -or [int]$d.count -notin @(1,20)){throw 'fresh Padding inputs required'}
$stage=[IO.Path]::GetFullPath($StageRoot);$pkg=[IO.Path]::GetFullPath($PackageRoot);New-Item -ItemType Directory -Path $pkg -Force|Out-Null
$rows=@();$refs=@($d.refs.GetEnumerator())
foreach($e in $refs){$r=$e.Value;if([string]::IsNullOrWhiteSpace([string]$r.path)){throw "missing ref $($e.Key)"};$p=[IO.Path]::GetFullPath([string]$r.path);$actual=H $p;if($actual -cne [string]$r.sha256 -or (Get-Item $p).Length -ne [int64]$r.bytes){throw "ref drift $($e.Key)"};$name=[IO.Path]::GetFileName($p);$dest=Join-Path $pkg ('inputs\'+$e.Key+'-'+$name);if(Test-Path $dest){throw 'destination collision'};New-Item -ItemType Directory -Path (Split-Path $dest) -Force|Out-Null;Copy-Item -LiteralPath $p -Destination $dest;$rows += [ordered]@{role=$e.Key;source=$p;staged=$dest;sha256=$actual;bytes=[int64](Get-Item $dest).Length}}
$planPath=[IO.Path]::GetFullPath($PlanPath);if(-not(Test-Path $planPath)){throw 'explicit plan missing'};Copy-Item -LiteralPath $planPath -Destination (Join-Path $pkg 'plan.json');$planHash=H (Join-Path $pkg 'plan.json') 2097152
$manifest=[ordered]@{kind='factory-padding-fresh-stage-v1';status='source-staged-prelaunch';count=$d.count;stageRoot=$stage;packageRoot=$pkg;sourceInputsPath=$src;sourceInputsHash=H $src 2097152;planPath=(Join-Path $pkg 'plan.json');planHash=$planHash;rows=$rows;nativeActions=0;compilerActions=0;lockActions=0}
New-Item -ItemType Directory -Path $stage -Force|Out-Null
$manifest|ConvertTo-Json -Depth 16|Set-Content -LiteralPath (Join-Path $stage 'stage-manifest.json') -Encoding UTF8
$manifest|ConvertTo-Json -Depth 16
