#!/usr/bin/env python3
"""Read-only exact-source controls; no PowerShell/native execution."""
import hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parent
repo=root.parents[3]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
original=repo/'factory/native/windows/stack-lifecycle-next-capture-v1/capture-repeat.ps1'
s=original.read_bytes();a=s.index(b'function Read-UIA(');b=s.index(b'$env:Path=',a)
assert (root/'read-uia.ps1').read_bytes()==s[a:b], 'Original Read-UIA bytes changed'
for name in ('cleanup.ps1','stream-seal.ps1'):
 assert (root/'support'/name).read_bytes()==(original.parent/'support'/name).read_bytes(),name
contract=json.loads((root/'worker-contract.json').read_text())
for x in contract['sourceBindings']:assert sha(root/x['path'])==x['sha256'],x['path']
ps=sorted(str(p.relative_to(root)) for p in root.rglob('*.ps1'))
assert ps==sorted(contract['powershellMembership'])
parent=(root/'invoke-worker.ps1').read_text()
for forbidden in ('Add-Type -AssemblyName UIAutomation','[Windows.Automation.','Read-UIA','WaitForPendingFinalizers','GC]::'):
 assert forbidden not in parent,forbidden
worker=(root/'worker.ps1').read_text()
assert worker.count('Read-UIA $element')==1
for forbidden in ('SetForegroundWindow','ShowWindow','PostMessage','SendMessage','WaitForPendingFinalizers','GC]::','FinalReleaseComObject'):
 assert forbidden not in worker,forbidden
assert 'AddSeconds(15)' in parent and 'task.Wait(5000)' in parent
assert parent.index('Assert-UiaSnapshotWorkerProof $proof')<parent.index('[pscustomobject]@{snapshotPath=')
print(json.dumps({'status':'passed-local-source-controls','checks':len(contract['sourceBindings'])+12,'originalCaptureSha256':sha(original),'readUiaSha256':sha(root/'read-uia.ps1'),'nativeExecuted':False},indent=2))
