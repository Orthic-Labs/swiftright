$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$repo='D:\Claude\swiftright';$zip=Join-Path $repo '.work\sr0-incremental-v5-source-r1.zip';$stage=Join-Path $repo '.work\sr0-incremental-v5-controls-r1'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne 'ac44539a3a988c2f97792bd7c183b5059e71171133fe7ca564dedbaa914d7f05'){throw 'Source archive drift'};if(Test-Path -LiteralPath $stage){throw 'Fresh stage required'};Expand-Archive -LiteralPath $zip -DestinationPath $stage
$mi=Get-Item -LiteralPath (Join-Path $stage 'stage-manifest.json');if($mi.Length -gt 1MB){throw 'Manifest bound'};$m=[IO.File]::ReadAllText($mi.FullName)|ConvertFrom-Json;$parsed=0
foreach($r in $m.files){$f=Join-Path $stage $r.path;$i=Get-Item -LiteralPath $f;if($i.Length -ne $r.bytes -or $i.Length -gt 1MB -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw 'Source entry drift'};if($f.EndsWith('.ps1')){$t=$null;$e=$null;$null=[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$t,[ref]$e);if($e.Count){throw ($r.path+': '+($e.Message -join ';'))};$parsed++}}
[ordered]@{kind='root-sr0-v5-parse-v1';parsed=$parsed;status='passed';nativeWindowActions=0;compilerActions=0;lockActions=0}|ConvertTo-Json
& (Join-Path $stage 'root-process-validation-v5\run-controls.ps1') -Stage $stage
