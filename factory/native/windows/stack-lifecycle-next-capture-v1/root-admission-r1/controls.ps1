$ErrorActionPreference='Stop'
$repo='D:\Claude\swiftright';$root=Join-Path $repo 'factory\native\windows\stack-lifecycle-next-capture-v1'
$manifest=Join-Path $root 'root-stage-manifest.json'
if((Get-FileHash $manifest).Hash.ToLowerInvariant() -cne '4cb0602f6ed2a50ee7717895ce1dc03d48e80e82909996f395fa1b1da93f7eb4'){throw 'Stage drift'}
$stage=Get-Content $manifest -Raw|ConvertFrom-Json
foreach($row in $stage.files){$file=Join-Path $repo $row.path;if((Get-FileHash $file).Hash.ToLowerInvariant() -cne $row.hash.Replace('sha256:','') -or (Get-Item $file).Length -ne $row.bytes){throw ('Source drift '+$row.path)};if($file.EndsWith('.ps1')){$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$t,[ref]$e);if(@($e).Count){throw ('AST errors '+$file)}}}
$out=Join-Path $root 'actual-controls-r1';if(Test-Path $out){throw 'Fresh output required'};New-Item -ItemType Directory -Path $out|Out-Null
& (Join-Path $root 'test-source-controls.ps1') -OutputPath (Join-Path $out 'source-control.json')
Get-Content (Join-Path $out 'source-control.json') -Raw
