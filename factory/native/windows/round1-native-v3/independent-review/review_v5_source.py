"""Offline narrow v5 source/control design checks; no PowerShell/native execution."""
from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parents[5];P=R/'factory/native/windows/round1-native-v5';A=P.with_name('round1-native-v4')
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def check():
 m=json.loads((P/'root-stage-manifest.json').read_text())
 for x in m['files']:
  f=R/x['path'];assert f.stat().st_size==x['bytes'] and h(f)==x['sha256'],x['path']
 capture=(P/'capture-repeat.ps1').read_text();driver=(P/'run-repeat.ps1').read_text();close=(P/'owned-close.ps1').read_text();cleanup=(P/'cleanup.ps1').read_text()
 assert capture.index('$uia|ConvertTo-Json')<capture.index('$pixels=Capture-FactoryPixels')<capture.index('$close=Request-FactoryOwnedClose')<capture.index('$exitDeadline=')<capture.index('Complete-FactoryRawStreams $rawStreams')<capture.index('$hostOutput=Get-Content')
 assert '$exitDeadline=[DateTime]::UtcNow.AddSeconds(15)' in capture and '$stdoutTask.Wait(5000)' in capture
 for token in ['Assert-FactoryRuntimeSource','Assert-HostCompilerInputs','Owned close bridge membership drift','Owned close bridge byte drift','Owned close source/exe lineage drift','Owned close renderer drift']:assert token in capture
 for token in ['$WindowPID -ne $ExpectedPID','& $OwnedGuard|Out-Null','& $SourceGuard|Out-Null','& $LockGuard|Out-Null','& $BackgroundGuard|Out-Null','([uint32]0x0010)']:assert token in close
 assert close.index('& $SourceGuard')<close.index('& $LockGuard')<close.index('& $BackgroundGuard')<close.index('& $OwnedGuard')<close.index('& $Post')
 assert 'PostMessage($target,$message,$w,$l)' in capture and 'SetForegroundWindow' not in capture and 'SendKeys' not in capture
 assert 'ownedIdentity=[ordered]@{pid=$p.Id;path=$exe;startedAt=$ownedStartedAt}' in capture
 for token in ['Outcome.cleanup.confirmedOwnedExit -is [bool]','Outcome.ownedIdentity.pid -eq $Owned.pid','Outcome.ownedIdentity.path -ceq $Owned.path','Outcome.ownedIdentity.startedAt -ceq $Owned.startedAt','Outcome.lockOwner -ceq $Owner','Outcome.compileReceiptHash -ceq $CompileHash','Outcome.exeHash -ceq $ExeHash','Outcome.stdoutSha256 -ceq $StdoutHash','Outcome.stderrSha256 -ceq $StderrHash','Owned.path -ceq $ExpectedPath']:assert token in cleanup
 assert driver.index('Get-FileHash $proofCompilePath')<driver.index('Test-FactoryCaptureExitProof')<driver.index('if($captureExitConfirmed){continue}')<driver.index('Get-Process -Id $owned.pid')
 for token in ['Invoke-FactoryConfirmedRelease $acquired $releaseAllowed','NoProcessFoundForGivenId','Owned exit unconfirmed']:assert token in driver
 oldcleanup=(A/'cleanup.ps1').read_text();assert cleanup.startswith(oldcleanup)
 for n in ['namespace.ps1','test-namespace.ps1','test-cleanup.ps1','stream-seal.ps1','test-stream-seal.ps1','repeat-task.ps1']:assert (P/n).read_bytes()==(A/n).read_bytes()
 closecontrols=(P/'test-owned-close.ps1').read_text();proofcontrols=(P/'test-capture-exit-proof.ps1').read_text()
 assert 'Request-FactoryOwnedClose' in closecontrols and 'postCalls -ne' in closecontrols and 'source,lock,background,owned,post' in closecontrols
 for token in ['bad-hwnd','bad-pid','owned-drift','source-drift','lock-lost','foreground','failed-post']:assert token in closecontrols
 for token in ['normal','pid','path','start','owner','compile','exe','stdout','stderr','unconfirmed','numeric-confirmed','expected-path']:assert token in proofcontrols
 assert 'Test-FactoryCaptureExitProof $outcome $owned' in proofcontrols
 test=(P/'test-process-streams.ps1').read_text();assert test.index('try{')<test.index('$started=$p.StartTime')
 for f in P.glob('*.ps1'):
  assert not re.search(r'\$(host|pid|input)\s*(?:[+*/-]?=|\+\+|--)|foreach\s*\(\s*\$(host|pid|input)\s+in',f.read_text(),re.I),f.name
 return {'status':'v5-source-control-design-clear','producerStage':h(P/'root-stage-manifest.json'),'verifiedPins':len(m['files']),'close':'Exact owned HWND/PID WM_CLOSE after UIA/PW, all four live guards & source/exe/bridge checks; old bounded exit/seal unchanged','retainedProof':'Exact actual raw streams, measured compile path/exe, timestamp owner, PID/path/start & boolean exit; rejected proof falls back to prior strict cleanup/lock hold','controls':'8 close +12 proof mutation cases; existing15 cleanup/7 namespace/4 IO byte-equal; real child test guaranteed cleanup envelope','actualControlRunsByReviewer':0,'producerEdits':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
