from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[4];HERE=Path(__file__).resolve().parent
h=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
def verify():
 r=(HERE/'capture-repeat.ps1').read_text();c=(HERE/'coordinator.ps1').read_text();p=json.loads((HERE/'capture-plan.json').read_text())
 assert all(x not in r for x in ['Windows.Automation','UIAutomationClient','UIAutomationTypes','Read-UIA'])
 assert r.index('Invoke-FactoryUiaSnapshotWorker $target')<r.index('$pixels=Capture-FactoryPixels')<r.index("'owned-close-request'")
 assert r.count('Assert-FactorySnapshotReady $workerResult $target')==3
 assert r.index('Initialize-FactoryFinalExitNative')<r.index('$p=[Diagnostics.Process]::Start')
 assert r.index('$retainedTimingHandle=$p.Handle')<r.index('$finalStart=[ordered]')<r.index('$stdoutFile=[IO.File]::Open')
 assert r.index("'capture-outcome.json')}")<r.index('$finalSample=Get-FactoryFinalExitSample')<r.index('Assert-FactoryCaptureOutcome $primaryError')
 assert "AddSeconds(15)" in r and '$stdoutTask.Wait(5000)' in r and '$stderrTask.Wait(5000)' in r
 assert "if(-not $validHost){throw 'Owned host output failed original validity predicate'}" in r
 for f in ['cleanup.ps1','stream-seal.ps1','owned-close.ps1','pixels-background.ps1','host-inputs.ps1','verify-runtime-source.ps1','lifecycle-timing.ps1']:
  assert (HERE/'support'/f).read_bytes()==(HERE.parent/'padding-window-diagnosis-capture-v1/support'/f).read_bytes()
 for f in ['invoke-worker.ps1','worker.ps1','schema.ps1','read-uia.ps1','worker-contract.json','test-pure.ps1','support/cleanup.ps1','support/stream-seal.ps1']:
  assert (HERE/'dependencies/uia-worker'/f).read_bytes()==(HERE.parent/'uia-snapshot-worker-v1'/f).read_bytes()
 assert (HERE/'support/final-exit-certificate.ps1').read_bytes()==(HERE.parent/'final-exit-certificate-v2/final-exit-certificate.ps1').read_bytes()
 assert c.index('Possible interactive worker start lacks')<c.index('Test-FactoryFinalReleaseProof')<c.index('Invoke-FactoryConfirmedRelease')
 assert "Final raw stream/outcome byte join mismatch" in c and "Final proof read outside exact closure" in c
 for b in json.loads((HERE/'integration-bindings.json').read_text())['files']:assert h(HERE/b['path'])==b['sha256']
 for name in ['capture-repeat.ps1','coordinator.ps1','dispatch.ps1','prepare-capture.ps1']:
  assert '[ValidateSet(1)]' in (HERE/name).read_text()
 obs=HERE.parent/'padding-window-diagnosis-build-v1/root-build-r1/actual/observation.json'
 assert p['admittedCompileReceiptSha256']==h(obs)
 assert p['admittedExeSha256']==json.loads(obs.read_text(encoding='utf-8-sig'))['exeSha256']
 return {'status':'passed','offlineSourceChecks':15,'nativeActions':0,'compilerActions':0,'powershellControls':'prepared/unrun'}
if __name__=='__main__':print(json.dumps(verify(),indent=2))
