import hashlib,json
from pathlib import Path
p=Path(__file__).resolve().parent;repo=p.parents[3];old=repo/'factory/native/windows/padding-window-diagnosis-capture-v2/dependencies/uia-worker'
for name in ['worker.ps1','read-uia.ps1','schema.ps1','support/cleanup.ps1','support/stream-seal.ps1']:
 assert (p/name).read_bytes()==(old/name).read_bytes(),name
s=(p/'invoke-worker.ps1').read_text()
assert s.index('Initialize-FactoryUiaFinalExitNative')<s.index('[Diagnostics.Process]::Start')
assert s.index("'worker-launch-attempt.json'")<s.index('[Diagnostics.Process]::Start')
assert s.index('Close-FactoryRawStreamDestination $s')<s.index('Get-FactoryUiaFinalExitSample $handle $finalStart')<s.index('$p.Dispose()')
assert s.index("'worker-exit.json') $proof")<s.index('Get-FactoryUiaFinalExitSample $handle $finalStart')
assert 'Get-FactoryUiaFinalExitSample $p.Handle' not in s
assert 'AddSeconds(15)' in s and 'task.Wait(5000)' in s
helper=(p/'support/final-exit-certificate.ps1').read_text()
assert 'compileReceipt' not in helper
assert 'WaitForSingleObject($OriginalRetainedHandle,0)' in helper
assert 'owner-release-only' in helper and 'Test-FactoryAllUiaWorkerReleaseProofs' in helper
c=json.loads((p/'worker-contract.json').read_text())
for b in c['sourceBindings']:assert hashlib.sha256((p/b['path']).read_bytes()).hexdigest()==b['sha256']
assert sorted(str(f.relative_to(p)) for f in p.rglob('*.ps1'))==sorted(c['powershellMembership'])
print(json.dumps({'status':'passed-source-controls','checks':20+len(c['sourceBindings']),'nativeExecuted':False,'windowsControlsExecuted':False},indent=2))
