from pathlib import Path
import hashlib,json
out=Path('factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-color-capture-r2')
actual=out/'failure-actual'
m=json.loads((actual/'archive-manifest.json').read_text())
assert not m['processes']
rows={r['path']:r for r in m['files']}
co=json.loads((actual/'control-count1-r1/coordinator.json').read_text(encoding='utf-8-sig'))
assert co['error']=='capture failed: Fresh safe factory worker output required'
assert co['taskParentProof']['kernelWait']==0 and co['taskParentProof']['dotNetExited']
assert co['taskParentProof']['kernelExitCodeSigned']==co['taskParentProof']['dotNetExitCode']==1
src=(out/'sources/overlay/all-owned-release-rectangle-r1.ps1').read_text()
start=src.index('function Assert-RootRectangleAllOwnedRelease(')
end=src.index(' $declaration=Get-Content',start)
renderer=src[start:end].replace('Assert-RootRectangleAllOwnedRelease','Assert-RootIncidentRendererRelease')+' return $true\n}\n'
script="""# Incident recovery only; failed native evidence remains rejected.
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle\\captures\\color-r2'
$Config=Get-Content -Raw -LiteralPath (Join-Path $Root 'control-count1-r1\\config.json')|ConvertFrom-Json
__PINS__
foreach($R in @($Config.sourceBindings)){if((Get-FileHash -LiteralPath (Join-Path $Config.overlayRoot $R.path)).Hash.ToLowerInvariant() -cne $R.sha256){throw 'incident overlay drift'}}
. $Config.integrationGuardPath
$Si=Get-Content -Raw -LiteralPath $Config.sourceInputsPath|ConvertFrom-Json
Assert-FactoryIntegrationSources $Config.producerRoot $Si|Out-Null
. (Join-Path $Config.producerRoot 'support\\final-exit-certificate.ps1')
__RENDERER__
$Co=Get-Content -Raw -LiteralPath (Join-Path $Root 'control-count1-r1\\coordinator.json')|ConvertFrom-Json
$Task=Get-Content -Raw -LiteralPath (Join-Path $Root 'control-count1-r1\\task-result.json')|ConvertFrom-Json
if($Co.status -cne 'failed' -or $Co.error -cne 'capture failed: Fresh safe factory worker output required' -or $Task.error -cne 'Fresh safe factory worker output required' -or $Co.owner -cne $Config.owner -or $Task.owner -cne $Co.owner -or $Co.taskParentProof.kernelWait -ne 0 -or -not $Co.taskParentProof.dotNetExited -or $Co.taskParentProof.kernelExitCodeSigned -ne 1 -or $Co.taskParentProof.dotNetExitCode -ne 1){throw 'incident parent lineage rejected'}
if($Task.memoryReceipt.activeProcessCount -ne 1 -or $Task.memoryReceipt.parentPid -ne $Co.taskParentProof.pid -or $Task.memoryReceipt.issuedMetadataHash -cne $Co.issuedMetadataHash){throw 'incident child quiescence rejected'}
$Dir=Join-Path $Config.runRoot 'native-01';$Worker=Join-Path $Dir 'uia-worker'
# Exact guard fails before directory creation, config creation or Process.Start.
$Invoker=Get-Content -LiteralPath (Join-Path $Config.overlayRoot 'uia-worker-invoke-v2.ps1') -Raw
$OldPrefix='D:\\Claude\\swiftright\\factory\\native\\windows\\'
if($Worker.StartsWith($OldPrefix,[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $Worker) -or $Invoker -notmatch [regex]::Escape("if(-not `$root.StartsWith('"+$OldPrefix+"'")){throw 'exact prelaunch rejection required'}
if(@(Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -like '*\\FactoryProbe.exe' -or $_.CommandLine -like '*captures\\color-r2*'}).Count){throw 'incident still has processes'}
Assert-RootIncidentRendererRelease $Dir $Co.owner $Si.compileReceiptPath $Co.compileReceiptHash $Si.exeRef.path $Co.exeHash $Si.sourceHash $Config.producerRoot $Si|Out-Null
$Lock='D:\\Claude\\desktop.lock';$S=[IO.File]::Open($Lock,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{$R=[IO.StreamReader]::new($S,[Text.Encoding]::UTF8,$true,1024,$true);try{$Old=$R.ReadToEnd().Trim()}finally{$R.Dispose()};if($Old -cne $Co.owner){throw 'incident lock owner changed'};$B=[Text.Encoding]::UTF8.GetBytes('free');$S.Position=0;$S.SetLength(0);$S.Write($B,0,$B.Length);$S.Flush($true)}finally{$S.Dispose()}
[ordered]@{kind='factory-incident-lock-recovery-v1';status='released-own-lock';owner=$Co.owner;rendererOriginalHandleProof=$true;parentOriginalHandleProof=$true;workerGuardRejectedBeforeLaunch=$true;nativeQualification='failed';failedReceiptUnchanged=$true;lockReleased=$true;finishedAt=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $Root 'control-count1-r1\\incident-recovery.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $Root 'control-count1-r1\\incident-recovery.json') -Raw
"""
pins='\n'.join("if((Get-FileHash -LiteralPath (Join-Path $Root '"+r['path'].replace('/','\\')+"')).Hash.ToLowerInvariant() -cne '"+r['sha256']+"'){throw 'archived incident bytes drift'}" for r in m['files'])
script=script.replace('__PINS__',pins).replace('__RENDERER__',renderer)
(out/'incident-release-r1.ps1').write_text(script)
print(json.dumps({'script':str(out/'incident-release-r1.ps1'),'sha256':hashlib.sha256(script.encode()).hexdigest()}))
