# Archive completed compile-only current67 hosts; no UI, input, stage write or deletion.
$ErrorActionPreference='Stop'
$root='D:\Claude\swiftright\factory\native\windows\primary-hosts-final-67b841fb-20261011'
$out=Join-Path $root 'compile-archive'
if(Test-Path $out){throw 'Fresh owned archive required'}
$expected='67b841fbbb5b8571a14390637bd875b62bf433ad'
$rows=@()
foreach($i in 1..10){
 $name='primary-{0:D2}' -f $i;$package=Join-Path $root ($name+'\package')
 $plan=Get-Content (Join-Path $package 'plan.json') -Raw|ConvertFrom-Json
 $observation=Get-Content (Join-Path $package 'observation.json') -Raw|ConvertFrom-Json
 if($plan.runtimeSourceCommit -cne $expected -or $observation.runtimeSourceCommit -cne $expected -or $observation.planSha256 -cne (Get-FileHash (Join-Path $package 'plan.json')).Hash.ToLowerInvariant()){throw 'Exact current67 compile joins required'}
 $dest=Join-Path $out $name;New-Item -ItemType Directory $dest|Out-Null
 foreach($file in @('plan.json','observation.json','runtime-source-receipt.json','runtime-source-tree.json','compile.stdout.txt','compile.stderr.txt')){Copy-Item (Join-Path $package $file) (Join-Path $dest $file)}
 if($observation.exitCode -eq 0){
  $exe=[IO.Path]::GetFullPath($observation.exePath)
  if(-not $exe.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash $exe).Hash.ToLowerInvariant() -cne $observation.exeSha256 -or $observation.exeSubsystem -ne 2){throw 'Actual owned GUI binary binding differs'}
  Copy-Item $exe (Join-Path $dest 'FactoryProbe.exe')
 }
 $rows+=[ordered]@{directory=$name;sourceHash=$plan.sourceHash;case=$plan.case;runtimeCommit=$expected;exitCode=$observation.exitCode;exeHash=$observation.exeSha256;subsystem=$observation.exeSubsystem;planHash=(Get-FileHash (Join-Path $dest 'plan.json')).Hash.ToLowerInvariant();observationHash=(Get-FileHash (Join-Path $dest 'observation.json')).Hash.ToLowerInvariant()}
}
[ordered]@{kind='actual-current67-primary-host-compile-archive';rows=$rows;nativeCaseCaptureCount=0;uiLaunched=$false;stageModified=$false}|ConvertTo-Json -Depth 10|Set-Content -Encoding UTF8 (Join-Path $out 'archive-receipt.json')
