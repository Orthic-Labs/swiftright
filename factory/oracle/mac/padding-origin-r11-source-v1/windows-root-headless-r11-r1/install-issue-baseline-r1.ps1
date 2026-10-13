$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\windows-replay-r11-headless-r1.zip';$stage='D:\Claude\swiftright\.factory-work\windows-replay-r11\headless-r1';$ns='D:\Claude\swiftright\.factory-work\windows-replay-r11'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne '3547a936942f0e27318e87a06300f7efdd3711f881ffbf77653630622b856104'){throw 'Source ZIP drift'}
if(Test-Path -LiteralPath $stage){throw 'Fresh stage required'};Expand-Archive -LiteralPath $zip -DestinationPath $stage
$m=[IO.File]::ReadAllText((Join-Path $stage 'stage-manifest.json'))|ConvertFrom-Json
foreach($r in $m.files){$f=Join-Path $stage $r.path;if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256 -or (Get-Item -LiteralPath $f).Length -ne $r.bytes){throw 'Stage hash drift'};if($f.EndsWith('.ps1')){$tokens=$null;$errs=$null;$ast=[System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errs);if($errs.Count){throw 'PS source parse failure'}}}
$builder='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis';$producer='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3'
$plan=Join-Path $builder 'package\plan.json';$receipt=Join-Path $builder 'package\build-capture-lease-r1\observation.json';$d=[IO.File]::ReadAllText($receipt)|ConvertFrom-Json;$exe=$d.exePath
$renderer='D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll';$canonical='D:\Claude\swiftright\factory\native\windows\canonical-inputs-v1\manifest.json';$binding=Join-Path $builder 'metadata\source-binding.json'
$run=Join-Path $ns 'replays\r1';$issued=Join-Path $ns 'coordinator-r1\issued-metadata.json';$serializer='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
function Hash([string]$p){(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant()}
$issuedRaw=& (Join-Path $stage 'sources\issue-count20-fresh-r11-v4.ps1') -FreshCasePath (Join-Path $stage 'inputs\fresh-case.json') -FreshTuplePath (Join-Path $stage 'inputs\fresh-tuple.json') -FreshManifestPath (Join-Path $stage 'inputs\fresh-manifest.json') -EquivalencePath (Join-Path $stage 'inputs\equivalence-v4.json') -ActualPlanPath $plan -ActualReceiptPath $receipt -ExecutablePath $exe -RendererPath $renderer -CanonicalInputsPath $canonical -SourceBindingPath $binding -NamespaceRoot $ns -RunRoot $run -OutputPath $issued -CompileReceiptSha256 (Hash $receipt) -ExeSha256 (Hash $exe) -PlanSha256 (Hash $plan) -SerializerControlSha256 $serializer -Count 20
[IO.File]::WriteAllText((Join-Path $stage 'issuer.stdout.json'),[string]($issuedRaw -join "`r`n"),[Text.UTF8Encoding]::new($false))
. (Join-Path $stage 'sources\integration-fresh-r11-v3.ps1')
$positive=Assert-LeaseIssuedMetadata -Path $issued -Hash (Hash $issued) -RunRoot $run -Count 20 -CompileHash (Hash $receipt) -ExeHash (Hash $exe) -SerializerHash $serializer -ProducerRoot $producer
if($positive.expectedCount -ne 20 -or $positive.case.id -cne 'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9'){throw 'Headless fresh baseline not admitted'}
$r=[ordered]@{kind='root-factory-fresh-issuer-integration-headless-v1';status='passed-baseline-only';issuedPath=$issued;issuedSha256=(Hash $issued);runRoot=$run;sourceFiles=$m.files.Count;nativeWindowActions=0;compilerActions=0;lockActions=0;at=[DateTimeOffset]::UtcNow.ToString('o')}
[IO.File]::WriteAllText((Join-Path $stage 'root-baseline.json'),($r|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false));$r|ConvertTo-Json -Depth 8
