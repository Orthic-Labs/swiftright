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
 assert '[ValidateSet(1,20)][int]$Count=20' in batch and 'for($i=1;$i -le $Count;$i++)' in batch and 'Namespace already exists; no reuse/retry' in batch and '$dispatch.lockReleased' in batch
 assert batch.count('Assert-ReplayInputs')>=4 and batch.count('Assert-RepeatNamespace')>=2
 contract=json.loads((PRODUCER/'contract.json').read_text());assert contract['allowedCounts']==[1,20] and contract['retry'] is False and len(contract['hosts'])==5
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
 seal=(PRODUCER/'stream-seal.ps1').read_text();io=(PRODUCER/'test-stream-seal.ps1').read_text()
 assert seal.index('$stream.task.GetAwaiter().GetResult()')<seal.index('$stream.file.Flush($true)')<seal.index('$stream.file.Dispose()')<seal.index('$stream.sealed=$true')
 assert 'if($stream.sealed){continue}' in seal and 'Raw stream completion deadline' in seal
 sealcall=capture.index('  Complete-FactoryRawStreams $rawStreams')
 assert sealcall<capture.index('  $hostOutput=Get-Content',sealcall)<capture.index('files=@(Get-ChildItem',sealcall)
 assert 'if($stream.sealed){continue}' in capture and capture.index('$stream.file.Dispose();$stream.sealed=$true')<capture.index('stdoutSha256=')
 for token in ['CopyToAsync($file)', 'ReadAllBytes($path)', 'Get-FileHash -LiteralPath $path', 'real-copy-close-read-hash-idempotent', "@('unfinished','faulted')", 'SetException', 'both-real-streams-sealed-all-file-hashes', '$hashes.Count -ne 5']:assert token in io
 for name in ['cleanup.ps1','namespace.ps1','test-cleanup.ps1','test-namespace.ps1','repeat-task.ps1']:
  assert (PRODUCER/name).read_bytes()==(REPO/'factory/native/windows/round1-repeat-cleanup-v2'/name).read_bytes(),name
 expected={'stack-overlay':'build-r1\\observation.json','custom-layout':'build-r1\\observation.json','padding-frame':'build-v2-r1\\observation.json','preference-key':'build-v2-r1\\observation.json','scroll-view':'build-v2-r1\\observation.json'}
 for host in contract['hosts']:
  assert host['receiptRelative']==expected[host['label']]
  assert host['package'] in driver and host['package'] in capture
  assert host['planHash'] in capture
  local=REPO/host['package'].split('\\swiftright\\',1)[1].replace('\\','/')/'plan.json'
  assert digest(local.read_bytes())==host['planHash']
 assert 'Measured compile receipt/exe pins required' in driver
 assert '$owner=' in driver and "+' '+[DateTimeOffset]::UtcNow.ToString('o')" in driver
 import re
 reserved=[]
 for item in manifest['files']:
  path=REPO/item['path']
  if path.suffix!='.ps1' or '/preimages/' in str(path) or '/lineage-' in str(path):continue
  for num,line in enumerate(path.read_text().splitlines(),1):
   if re.search(r'\$(host|pid|input)\s*(?:[+*/-]?=|\+\+|--)|foreach\s*\(\s*\$(host|pid|input)\s+in',line,re.I):reserved.append([item['path'],num,line])
 assert not reserved,reserved
 return {'schema':'native-v3-static-independent-review-v1','stageSha256':digest((PRODUCER/'root-stage-manifest.json').read_bytes()),'verifiedPins':len(rows),'scope':'Static exact source/input closure only; no PowerShell execution or native claim','sourceChecks':'161 exact pins; five exact plans/routes; fresh1or20; stable owned cleanup; streams sealed before reads/hashes; real IO fault design; reserved-variable audit; timestamp owner protocol','producerEdits':0,'nativeRuns':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
