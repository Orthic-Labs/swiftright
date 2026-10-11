"""Read-only static source/pin replay, not PowerShell execution or native evidence."""
from pathlib import Path
import hashlib,json
HERE=Path(__file__).resolve().parent
PRODUCER=HERE.parent
REPO=PRODUCER.parents[3]
def digest(b):return hashlib.sha256(b).hexdigest()
def check():
 manifest=json.loads((PRODUCER/'root-stage-manifest.json').read_text());rows=[]
 for item in manifest['files']:
  p=REPO/item['path'];b=p.read_bytes();assert len(b)==item['bytes'] and digest(b)==item['sha256'],item['path'];rows.append(item)
 cleanup=(PRODUCER/'cleanup.ps1').read_text();capture=(PRODUCER/'capture-repeat.ps1').read_text();driver=(PRODUCER/'run-repeat.ps1').read_text();batch=(PRODUCER/'run-batch.ps1').read_text();tests=(PRODUCER/'test-cleanup.ps1').read_text()
 assert cleanup.index('$retainedHandle=$Process.Handle')<cleanup.index('$fresh=& $Lookup')<cleanup.index('$Process.Kill()')
 assert 'Retained process identity drift' in cleanup and 'Stable process handle unavailable' in cleanup
 assert '$Process.WaitForExit($WaitMilliseconds)' in cleanup and 'Owned cleanup exit unconfirmed' in cleanup
 assert '$fresh.Path -ne $Path' in cleanup and '$fresh.StartTime' in cleanup
 assert 'Exited process lacks known Start lineage' in cleanup and '-KnownStartedIdentity' in capture
 assert 'Stop-Process' not in cleanup and 'taskkill' not in cleanup
 started=capture.index('$p=[Diagnostics.Process]::Start($startInfo)');guarded=capture.index(' try {',started)
 assert guarded<capture.index('$stdoutFile=[IO.File]::Open',started)<capture.index('BaseStream.CopyToAsync',started)
 assert 'ReadToEndAsync' not in capture
 assert 'stdoutSha256=' in capture and 'stderrSha256=' in capture and 'streamErrors=' in capture
 assert 'for($i=1;$i -le 20;$i++)' in batch and 'Namespace already exists; no reuse/retry' in batch and '$dispatch.lockReleased' in batch
 assert batch.count('Assert-ReplayInputs')>=4 and batch.count('Assert-RepeatNamespace')>=2
 contract=json.loads((PRODUCER/'contract.json').read_text());assert contract['count']==20 and contract['retry'] is False and len(contract['hosts'])==2
 for h in contract['hosts']:
  for binding in h['bindings']:
   relative=binding['path'].split('\\swiftright\\',1)[1].replace('\\','/');assert digest((REPO/relative).read_bytes())==binding['sha256'],relative
 assert 'Assert-FactoryCaptureOutcome $primaryError $cleanupResult $streamErrors' in capture
 assert cleanup.index('if($null -ne $PrimaryError){throw $PrimaryError}')<cleanup.index("if(-not $Cleanup.confirmedOwnedExit")
 assert 'Assert-FactoryCaptureOutcome $primary $r $errors' in tests and '$caught.Exception.Message -ne $primary.Exception.Message' in tests
 for token in ['retained-path','retained-start','zero-handle','unproven-exit','receipt-write-failure','exit-race','timeout']:assert token in tests
 assert 'Invoke-FactoryConfirmedRelease $acquired $releaseAllowed' in driver
 assert 'if(-not $cleanup.confirmedOwnedExit){$releaseAllowed=$false' in driver and "NoProcessFoundForGivenId*" in driver
 assert '$script:releaseCalls' in tests and 'Invoke-FactoryConfirmedRelease $case.acquired $case.confirmed' in tests
 return {'schema':'cleanup-v2-static-independent-review-v1','stageSha256':digest((PRODUCER/'root-stage-manifest.json').read_bytes()),'verifiedPins':len(rows),'scope':'Static exact source/input closure only; no PowerShell execution or native claim','sourceChecks':'stable retained handle before identity/Kill; both identities; bounded confirmed exit; raw byte streams finally-covered; fresh20/source/namespace guards','producerEdits':0,'nativeRuns':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
