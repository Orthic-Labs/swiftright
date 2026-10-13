from pathlib import Path
import json,hashlib
HERE=Path(__file__).resolve().parent
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def verify():
 r=(HERE/'capture-repeat.ps1').read_text();c=(HERE/'coordinator.ps1').read_text();p=json.loads((HERE/'capture-plan.json').read_text())
 assert all(x not in r for x in ['UIAutomationClient','UIAutomationTypes','Windows.Automation','Read-UIA'])
 assert r.index('Invoke-FactoryUiaSnapshotWorker $target')<r.index('$pixels=Capture-FactoryPixels')<r.index("'owned-close-request'")
 assert r.count('Assert-FactorySnapshotReady $workerResult $target')==3
 assert r.index('$workerAttempted=$true')<r.index('Invoke-FactoryUiaSnapshotWorker $target')
 assert r.index("'declared-worker-inventory.json') $inventory")<r.index('$p=[Diagnostics.Process]::Start')
 assert r.index('Assert-LeaseIssuedMetadata $IssuedMetadataPath')<r.index('$p=[Diagnostics.Process]::Start')
 assert r.index('Initialize-FactoryFinalExitNative')<r.index('$p=[Diagnostics.Process]::Start')
 assert r.index("'capture-outcome.json')}")<r.index('$finalSample=Get-FactoryFinalExitSample')<r.index('Assert-FactoryCaptureOutcome $primaryError')
 assert r.index("$exitDeadline=[DateTime]::UtcNow.AddSeconds(15)")<r.index('$ordering.ownedCloseEndTicks=')
 assert "$startInfo.Arguments='--factory-capture-lease-seconds=40'" in r
 assert '$stdoutTask.Wait(5000)' in r and '$stderrTask.Wait(5000)' in r
 assert "if(-not $validHost){throw 'Owned host output failed original validity predicate'}" in r
 assert c.index('Possible interactive worker start lacks')<c.index('Assert-FactoryAllOwnedRelease $dir.FullName')<c.index('Invoke-FactoryConfirmedRelease')
 assert 'Terminal task worker inventory raw binding mismatch' in c
 assert c.index('Assert-PaddingFirstCaptureProof')<c.index("New-Item -ItemType Directory -Path $controlRoot")
 for f in ['capture-repeat.ps1','coordinator.ps1','dispatch.ps1']:
  t=(HERE/f).read_text();assert '[ValidateSet(1,20)]' in t and 'Assert-PaddingFirstCaptureProof' in t
 for f in ['cleanup.ps1','stream-seal.ps1','owned-close.ps1','pixels-background.ps1','host-inputs.ps1','verify-runtime-source.ps1','lifecycle-timing.ps1','final-exit-certificate.ps1']:
  assert (HERE/'support'/f).read_bytes()==(HERE.parent/'padding-window-diagnosis-capture-v2/support'/f).read_bytes()
 for q in (HERE.parent/'uia-worker-final-release-v1').rglob('*'):
  if q.is_file() and not any(x.startswith('independent-review') for x in q.parts) and '__pycache__' not in q.parts:
   assert (HERE/'dependencies/uia-worker'/q.relative_to(HERE.parent/'uia-worker-final-release-v1')).read_bytes()==q.read_bytes()
 for row in json.loads((HERE/'integration-bindings.json').read_text())['files']:assert h(HERE/row['path'])==row['sha256']
 assert p['compiledPlanSha256']=='sha256:'+h(HERE.parent/'padding-capture-lease-build-v1/package/plan.json')
 assert p['launchPreflightSha256']=='sha256:'+h(HERE.parent/'padding-capture-lease-build-v1/preflight.ps1')
 assert p['actualBuild']['compileReceiptSha256']=='1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf'
 assert p['actualBuild']['exeSha256']=='3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a'
 assert r.count("'capture-ordering.json') $ordering")==1
 assert r.count("'owned-worker-inventory.json') $inventory")==2
 assert "if(-not $workerAttempted){try{Write-FactoryDiagnosticJson" in r
 assert "Exact prelaunch worker declaration required" in (HERE/'support/all-owned-release.ps1').read_text()
 return {'status':'passed','offlineSourceChecks':25,'nativeActions':0,'compilerActions':0,'windowsControls':'prepared/unrun'}
if __name__=='__main__':print(json.dumps(verify(),indent=2))
