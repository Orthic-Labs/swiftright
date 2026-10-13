$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$zip=Join-Path $repo '.work\sr0-incremental-v4-source-r1.zip';$stage=Join-Path $repo '.work\sr0-incremental-v4-controls-r1'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'd38797f0f35fbe74ed6046ed90ead4df17bf6a104e87692cc0fd498170b5ee81'){throw 'Source archive drift'};if(Test-Path -LiteralPath $stage){throw 'Fresh stage required'};Expand-Archive -LiteralPath $zip -DestinationPath $stage
$mi=Get-Item -LiteralPath (Join-Path $stage 'stage-manifest.json');if($mi.Length -gt 1MB){throw 'Manifest bound'};$m=[IO.File]::ReadAllText($mi.FullName)|ConvertFrom-Json;$parsed=0
foreach($r in $m.files){$f=Join-Path $stage $r.path;$i=Get-Item -LiteralPath $f;if($i.Length -ne $r.bytes -or $i.Length -gt 1MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Source entry drift'};if($f.EndsWith('.ps1')){$t=$null;$e=$null;$null=[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$t,[ref]$e);if($e.Count){throw ($r.path+': '+($e.Message -join ';'))};$parsed++}}
[ordered]@{kind='root-sr0-v4-parse-v1';parsed=$parsed;status='passed';nativeWindowActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json
& (Join-Path $stage 'root-process-validation-v4\run-controls.ps1') -Stage $stage
