# Incident recovery only; failed native evidence remains rejected.
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='D:\Claude\swiftright\.factory-work\hosts\rectangle\captures\color-r2'
$Config=Get-Content -Raw -LiteralPath (Join-Path $Root 'control-count1-r1\config.json')|ConvertFrom-Json
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\capture-preflight.json')).Hash.ToLowerInvariant() -cne '76d9af225757cdab99688bae5c144561abcfd097b97a62aa1ffd9a99b4e57788'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\config-template.json')).Hash.ToLowerInvariant() -cne '38bbc56296ea02cc1ce68bf8c728c83f73704db8edf15b988039e3c4bc5529a3'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\config.json')).Hash.ToLowerInvariant() -cne '9a2740bcc28db05e866720c1e4636104cec181dd6fefce7bea722249fb576675'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\coordinator.json')).Hash.ToLowerInvariant() -cne 'b1e97dff9d41526af5687610be894459f06178c14067593741c1c3864a9979b2'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\desktop-availability.json')).Hash.ToLowerInvariant() -cne '3573a012e05888e49100894036a00d53c8a8df939e79ad2c0600f8b90bb0f945'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\dispatch-1.json')).Hash.ToLowerInvariant() -cne '6eafab49160eed32b706c604d8c0cd9f17fe5a9a4cdeb69faa77eec0d4aebdc5'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\hidden-task.vbs')).Hash.ToLowerInvariant() -cne '248a52f6399e320f1a6d8de7b6e5c15f1acb970b737b2a25b41591b8179f36f4'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\integration-controls.json')).Hash.ToLowerInvariant() -cne '3407186ecbede77ec3d678caf632dc3b87fdd68d099aba6ca31dc570a5aebbb0'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\mta-config-controls.json')).Hash.ToLowerInvariant() -cne '7f651fc7431caa9ab3fc653c29dad77885ab1670c74473545ccdc5334e3e6b6f'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\root-preflight.json')).Hash.ToLowerInvariant() -cne '155f516e5a227c1bcdf67116b48f2e1b61605d82ae235bcf5c89014278aac9b6'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\scheduled-task-receipt.json')).Hash.ToLowerInvariant() -cne 'ae771cc17f2e199478d7cb5c9e3efe96a001714fddc3a8cbc41f4f7ff2c5327b'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\task-result.json')).Hash.ToLowerInvariant() -cne '7ae14a1a11583119357f2f165a3a977cf46516395aed2b643777c04bb104e995'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\task-start.json')).Hash.ToLowerInvariant() -cne 'e0bf383d1c71cb7fd6d89aaeffc07266c371d188c34d7f4d507ce23407ad14b0'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\task.log')).Hash.ToLowerInvariant() -cne '33c37b2e54deb4f6bd5de1eaa80eabf712a9f713576a385b9763bfe321ad658f'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'control-count1-r1\uia-mta-controls.json')).Hash.ToLowerInvariant() -cne '6af089c3086a4eb3d9544ec2a1869fae48b9b6feaa4bf647413a5c26002422ce'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\candidate-binding.json')).Hash.ToLowerInvariant() -cne 'f12a56484695febc8237c57eeea3d4059371d94e85a56bd87c29f112621fbfbf'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\candidate-tuple.json')).Hash.ToLowerInvariant() -cne 'e3cbb552789ce879f383f8dfcff39b9c26108e391be40ef7f267cd1e89f435e4'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\host-inputs.ps1')).Hash.ToLowerInvariant() -cne '93c5c8e29999796f2c8a1c0689f384e3ea8b99d9e655c3e2a98e52baa27e49db'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\issued-metadata.json')).Hash.ToLowerInvariant() -cne 'f1a0dd60c2df3a0fdf1f008d10c92d9ec7e55067946adb1dc62172f4f0965139'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\observation.json')).Hash.ToLowerInvariant() -cne '75e829ce130a2a4d3da3568ecc3c4c26488269e5ac500d54d0997314ecc092f1'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Package.swift')).Hash.ToLowerInvariant() -cne '74a9751d7d21740585115d8d4042455b236d4c7d96132ec1b74836c6aca1858f'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\pixels-background.ps1')).Hash.ToLowerInvariant() -cne '7172bf8d69f2523672dc57e6ba2889951ea4db4a89100b8b5b42c2bdef2da6ef'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\plan.json')).Hash.ToLowerInvariant() -cne '802d064cfd971585e73d1f7d9fce969876029b93d04e7296f22a64f71b211c30'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\runtime-source-receipt.json')).Hash.ToLowerInvariant() -cne 'b28564f02cd32b96d348626a92e67c231d0ea5919ae93e836c9e6cfdb47d2fb7'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\runtime-source-tree.json')).Hash.ToLowerInvariant() -cne 'c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\capture-outcome.json')).Hash.ToLowerInvariant() -cne '123fe5e97c69fdc81b3a051fbfb695665de4b7b971576424148bccde6ad77fbf'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\declared-worker-inventory.json')).Hash.ToLowerInvariant() -cne '830301f42260576dfaf130d540ad0851159044388cfb071d9defc46c912b2c1a'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\final-exit-certificate.json')).Hash.ToLowerInvariant() -cne '72a8738ee2981483dbee335b469f5a42d79199cc401f01722b40644730a16dbd'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\final-start.json')).Hash.ToLowerInvariant() -cne 'b4434ccfd44e45c1adfbdf83d26ca198a08ebf78368c4c8d9a6148aff712e27c'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\host.stderr.txt')).Hash.ToLowerInvariant() -cne 'ef7175d9ec9d1c6f9d168032a66ae0ce24b62f20f0be4e46fd701c7779f0dae1'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\host.stdout.txt')).Hash.ToLowerInvariant() -cne 'e8f8d1b5737ec9a004a692278c02552c8b0f898a834a0f422bfcec927ece99c6'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\launch-observation.json')).Hash.ToLowerInvariant() -cne 'f0af233194c4651955bbac9ce3d7018bc040d98dc8077225d5e3c9b88aee3944'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\lifecycle-timing.json')).Hash.ToLowerInvariant() -cne '058d3289abe050b00887f7b5f42f1792f3ec85e851346225829e0665b2dca1c9'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\measured-capture-identity.json')).Hash.ToLowerInvariant() -cne '52537b0684b796d4d5217723aa9fdf3d2f0b940d5fca9fda11b2e80babd45c3c'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\owned-process.json')).Hash.ToLowerInvariant() -cne '627b2c9bef7cb1677e63c0831ee32ec3a3fba083d32ecece0f55f8c6c54bf13c'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\owned-window-inventory-after-process-start.json')).Hash.ToLowerInvariant() -cne '3c0eaf219ac2d3d866fadcf1011e51ffb6048189ca42a3d3402238567c40ed3c'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\owned-worker-inventory.json')).Hash.ToLowerInvariant() -cne '818cf95da35dfe86b9f120a9fa68ad69521301947db9bee6ed427a2ebf08e50a'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\native-01\terminal-worker.json')).Hash.ToLowerInvariant() -cne 'c1e77fc75c9024bd55aa50a189fc7ebeff4c21942a9d13f84551880de9ac3bb0'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\CaptureLease.swift')).Hash.ToLowerInvariant() -cne 'a544682735f732fae73c134c718886d19a7bef542aef5a9aaebc78d049f7c222'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\FactoryContainer.swift')).Hash.ToLowerInvariant() -cne '742dba1f12b2b2969779b8e525bfb699238f898f951693b67449d3c1dedeffa4'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\FactoryFill.swift')).Hash.ToLowerInvariant() -cne '21da245416c4bc6bd04981269546236e2a4c9d06dea4ecf2bd0664bf4dccf96f'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\FactoryTextGeometry.swift')).Hash.ToLowerInvariant() -cne '1063aea5475987cb356ac31d67b965206a9ca6383bcd66ed1fc4c366dbaf7d43'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\FactoryViewport.swift')).Hash.ToLowerInvariant() -cne '19a6fe4545d538c727d13fb025a8d13938ed6f39797db9769269b53c3b229c03'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\main.swift')).Hash.ToLowerInvariant() -cne '1ac0c0d8d67ec4d1e3d2111475827b10c14ae920b2f42cf289702029f80b4e65'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\MetricsLogging.swift')).Hash.ToLowerInvariant() -cne '2a590250fd2ff7f0266d9a1f1ccece396b84d5d2866ae6995f1e356bb53f2da4'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\MetricsPayload.swift')).Hash.ToLowerInvariant() -cne 'cde9a9a3a90f52eda4134069f7c6be80ad0d7315689c8e2cdc7ae21deb0f19e1'){throw 'archived incident bytes drift'}
if((Get-FileHash -LiteralPath (Join-Path $Root 'native\count1-r1\Sources\FactoryProbe\Witness.swift')).Hash.ToLowerInvariant() -cne '5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d'){throw 'archived incident bytes drift'}
foreach($R in @($Config.sourceBindings)){if((Get-FileHash -LiteralPath (Join-Path $Config.overlayRoot $R.path)).Hash.ToLowerInvariant() -cne $R.sha256){throw 'incident overlay drift'}}
. $Config.integrationGuardPath
$Si=Get-Content -Raw -LiteralPath $Config.sourceInputsPath|ConvertFrom-Json
Assert-FactoryIntegrationSources $Config.producerRoot $Si|Out-Null
. (Join-Path $Config.producerRoot 'support\final-exit-certificate.ps1')
function Assert-RootIncidentRendererRelease([string]$Directory,[string]$Owner,[string]$CompilePath,[string]$CompileHash,[string]$Exe,[string]$ExeHash,[string]$SourceHash,[string]$ProducerRoot,[object]$SourceInputs){
 Assert-FactoryIntegrationSources $ProducerRoot $SourceInputs
 $owned=Get-Content -Raw -LiteralPath (Join-Path $Directory 'owned-process.json')|ConvertFrom-Json
 $outcomePath=Join-Path $Directory 'capture-outcome.json';$outcome=Get-Content -Raw -LiteralPath $outcomePath|ConvertFrom-Json
 if($outcome.lockOwner -cne $Owner -or $outcome.sourceHash -cne $SourceHash -or $outcome.compileReceiptHash -cne $CompileHash -or $outcome.exeHash -cne $ExeHash){throw 'Renderer original outcome lineage mismatch'}
 $workerPath=Join-Path $Directory 'terminal-worker.json';$certPath=Join-Path $Directory 'final-exit-certificate.json'
 $expected=Get-Content -Raw -LiteralPath (Join-Path $Directory 'final-start.json')|ConvertFrom-Json
 if(-not(Test-FactoryFinalStart $expected) -or $expected.pid -ne $owned.pid -or $expected.path -cne $Exe -or $expected.startedAt -cne $owned.startedAt -or $expected.lockOwner -cne $Owner -or $expected.workerId -cne $Directory -or $expected.compileReceiptHash -cne $CompileHash -or $expected.exeHash -cne $ExeHash){throw 'Renderer final start original lineage mismatch'}
 $expected|Add-Member workerReceiptRef $workerPath;$expected|Add-Member workerReceiptHash ((Get-FileHash -LiteralPath $workerPath).Hash.ToLowerInvariant());$expected|Add-Member compileReceiptRef $CompilePath;$expected|Add-Member exeRef $Exe
 $certificate=Get-Content -Raw -LiteralPath $certPath|ConvertFrom-Json
 $terminal=Get-Content -Raw -LiteralPath $workerPath|ConvertFrom-Json
 if($terminal.finalCertificateRef -cne $certPath -or $terminal.originalOutcomeRef -cne $outcomePath -or $terminal.originalOutcomeHash -cne (Get-FileHash -LiteralPath $outcomePath).Hash.ToLowerInvariant()){throw 'Renderer terminal/outcome reference mismatch'}
 foreach($raw in @($certificate.rawStreams)){
  $requiredPath=Join-Path $Directory ('host.'+$raw.name+'.txt');$hash=if($raw.name -ceq 'stdout'){$outcome.stdoutSha256}elseif($raw.name -ceq 'stderr'){$outcome.stderrSha256}else{throw 'Unknown renderer final stream'}
  if($raw.path -cne $requiredPath -or $raw.sha256 -cne $hash){throw 'Renderer final raw/outcome mismatch'}
 }
 $allowedRefs=@($workerPath,$certPath,$CompilePath,$Exe,(Join-Path $Directory 'host.stdout.txt'),(Join-Path $Directory 'host.stderr.txt'))
 $reader={param($ref) if($allowedRefs -cnotcontains $ref){throw 'Renderer final read outside exact closure'};return ,([IO.File]::ReadAllBytes($ref))}
 if(-not(Test-FactoryFinalReleaseProof $certificate $expected $reader)){throw 'Renderer final original handle proof absent'}
 return $true
}

$Co=Get-Content -Raw -LiteralPath (Join-Path $Root 'control-count1-r1\coordinator.json')|ConvertFrom-Json
$Task=Get-Content -Raw -LiteralPath (Join-Path $Root 'control-count1-r1\task-result.json')|ConvertFrom-Json
if($Co.status -cne 'failed' -or $Co.error -cne 'capture failed: Fresh safe factory worker output required' -or $Task.error -cne 'Fresh safe factory worker output required' -or $Co.owner -cne $Config.owner -or $Task.owner -cne $Co.owner -or $Co.taskParentProof.kernelWait -ne 0 -or -not $Co.taskParentProof.dotNetExited -or $Co.taskParentProof.kernelExitCodeSigned -ne 1 -or $Co.taskParentProof.dotNetExitCode -ne 1){throw 'incident parent lineage rejected'}
if($Task.memoryReceipt.activeProcessCount -ne 1 -or $Task.memoryReceipt.parentPid -ne $Co.taskParentProof.pid -or $Task.memoryReceipt.issuedMetadataHash -cne $Co.issuedMetadataHash){throw 'incident child quiescence rejected'}
$Dir=Join-Path $Config.runRoot 'native-01';$Worker=Join-Path $Dir 'uia-worker'
# Exact guard fails before directory creation, config creation or Process.Start.
$Invoker=Get-Content -LiteralPath (Join-Path $Config.overlayRoot 'uia-worker-invoke-v2.ps1') -Raw
$OldPrefix='D:\Claude\swiftright\factory\native\windows\'
if($Worker.StartsWith($OldPrefix,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $Worker) -or $Invoker -notmatch [regex]::Escape("if(-not `$root.StartsWith('"+$OldPrefix+"'")){throw 'exact prelaunch rejection required'}
if(@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -like '*\FactoryProbe.exe' -or $_.CommandLine -like '*captures\color-r2*'}).Count){throw 'incident still has processes'}
Assert-RootIncidentRendererRelease $Dir $Co.owner $Si.compileReceiptPath $Co.compileReceiptHash $Si.exeRef.path $Co.exeHash $Si.sourceHash $Config.producerRoot $Si|Out-Null
$Lock='D:\Claude\desktop.lock';$S=[IO.File]::Open($Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{$R=[IO.StreamReader]::new($S,[Text.Encoding]::UTF8,$true,1024,$true);try{$Old=$R.ReadToEnd().Trim()}finally{$R.Dispose()};if($Old -cne $Co.owner){throw 'incident lock owner changed'};$B=[Text.Encoding]::UTF8.GetBytes('free');$S.Position=0;$S.SetLength(0);$S.Write($B,0,$B.Length);$S.Flush($true)}finally{$S.Dispose()}
[ordered]@{kind='factory-incident-lock-recovery-v1';status='released-own-lock';owner=$Co.owner;rendererOriginalHandleProof=$true;parentOriginalHandleProof=$true;workerGuardRejectedBeforeLaunch=$true;nativeQualification='failed';failedReceiptUnchanged=$true;lockReleased=$true;finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Root 'control-count1-r1\incident-recovery.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $Root 'control-count1-r1\incident-recovery.json') -Raw
