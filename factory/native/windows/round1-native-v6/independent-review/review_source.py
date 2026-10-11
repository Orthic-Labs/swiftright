"""Offline narrow v5 source/control design checks; no PowerShell/native execution."""
from pathlib import Path
import hashlib,json,re
R=Path(__file__).resolve().parents[5];P=R/'factory/native/windows/round1-native-v6';A=P.with_name('round1-native-v5')
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
 assert (P/'cleanup.ps1').read_bytes()==(A/'cleanup.ps1').read_bytes()
 for n in ['namespace.ps1','test-namespace.ps1','test-cleanup.ps1','stream-seal.ps1','test-stream-seal.ps1','repeat-task.ps1']:assert (P/n).read_bytes()==(A/n).read_bytes()
 closecontrols=(P/'test-owned-close.ps1').read_text();proofcontrols=(P/'test-capture-exit-proof.ps1').read_text()
 assert 'Request-FactoryOwnedClose' in closecontrols and 'postCalls -ne' in closecontrols and 'source,lock,background,owned,post' in closecontrols
 for token in ['bad-hwnd','bad-pid','owned-drift','source-drift','lock-lost','foreground','failed-post']:assert token in closecontrols
 for token in ['normal','pid','path','start','owner','compile','exe','stdout','stderr','unconfirmed','numeric-confirmed','expected-path']:assert token in proofcontrols
 assert 'Test-FactoryCaptureExitProof $outcome $owned' in proofcontrols
 test=(P/'test-process-streams.ps1').read_text();assert test.index('try{')<test.index('$started=$p.StartTime')
 for f in P.glob('*.ps1'):
  assert not re.search(r'\$(host|pid|input)\s*(?:[+*/-]?=|\+\+|--)|foreach\s*\(\s*\$(host|pid|input)\s+in',f.read_text(),re.I),f.name
 startup=(P/'startup-state.ps1').read_text();tests=(P/'test-startup-state.ps1').read_text()
 assert "originalSixSecondBreach=($ElapsedSeconds -gt 6)" in startup and "$ElapsedSeconds -gt 30" in startup
 assert startup.index("if($Exited){'exited'}")<startup.index("elseif($ElapsedSeconds -gt 30){'deadline'}")<startup.index("elseif($Hwnd -ne 0){'ready'}")
 for token in ['IsNaN','IsInfinity','$ElapsedSeconds -lt 0','$Exited -isnot [bool]']:assert token in startup
 assert '$sampleExited=$p.HasExited;' in capture and 'hasExited=$sampleExited' in capture
 assert '$startupFrequency=[Diagnostics.Stopwatch]::Frequency' in capture and '(($sampleTicks-$startupOriginTicks)/[double]$startupFrequency) $sampleExited' in capture
 assert capture.index('$launchRequestTicks=[Diagnostics.Stopwatch]::GetTimestamp()')<capture.index('$p=[Diagnostics.Process]::Start')<capture.index('$launchReturnTicks=[Diagnostics.Stopwatch]::GetTimestamp()')<capture.index('$startupOriginTicks=[Diagnostics.Stopwatch]::GetTimestamp()')
 assert 'Assert-Background $p.Id $dir $foregroundBefore;Check-Lock' in capture and 'originalLimitSeconds=6;diagnosticLimitSeconds=30;' in capture and 'startup-diagnostic.json' in capture
 assert 'raw host streams retained separately after sealing; no inferred native event timestamps' in capture
 for token in ['before6-no-window','exact6-ready','late-ready-retains-breach','exact30-no-window','over30-window-not-success','exit-priority','invalid-duration','numeric-exited']:assert token in tests
 assert 'Get-FactoryStartupState $caseRow.time $caseRow.exited $caseRow.hwnd' in tests
 return {'status':'v6-source-control-design-clear','startup':'Monotonic polling with10 semantic controls; original6s breach explicit, bounded30s diagnostic; separate actual launch request/return stamps; one exited sample shared by decision/receipt; each poll background/lock guards','producerStage':h(P/'root-stage-manifest.json'),'verifiedPins':len(m['files']),'close':'Exact owned HWND/PID WM_CLOSE after UIA/PW, all four live guards & source/exe/bridge checks; old bounded exit/seal unchanged','retainedProof':'Exact actual raw streams, measured compile path/exe, timestamp owner, PID/path/start & boolean exit; rejected proof falls back to prior strict cleanup/lock hold','controls':'Existing8 close/12 proof/15 cleanup/7 namespace/4 IO byte-equal; new10 startup decision controls prepared','actualControlRunsByReviewer':0,'producerEdits':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
