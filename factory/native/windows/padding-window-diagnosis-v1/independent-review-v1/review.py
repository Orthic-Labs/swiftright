from pathlib import Path
import hashlib,json,re
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/native/windows/padding-window-diagnosis-v1';B=R/'factory/native/windows/padding-settled-metrics-v2/package';O=P/'independent-review-v1'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
m=json.loads((P/'source-manifest.json').read_text())
for row in m['files']:assert sha(P/row['path'])==row['sha256'] and (P/row['path']).stat().st_size==row['bytes']
for name in ['Sources/FactoryProbe/Witness.swift','Sources/FactoryProbe/FactoryContainer.swift','Sources/FactoryProbe/FactoryFill.swift','Sources/FactoryProbe/FactoryTextGeometry.swift','Sources/FactoryProbe/MetricsPayload.swift','witness.manifest.json','runtime-source-tree.json','runtime-source-receipt.json']:assert (P/'package'/name).read_bytes()==(B/name).read_bytes()
main=(P/'package/Sources/FactoryProbe/main.swift').read_text();normal=main.replace('    var windowClosed = false\n','').replace(', windowClosed: windowClosed','').replace('            host.windowClosed = true\n','').replace(', phase: "tick"','');assert normal==(B/'Sources/FactoryProbe/main.swift').read_text()
logger=(P/'package/Sources/FactoryProbe/MetricsLogging.swift').read_text();normal=logger.replace(', windowClosed: Bool = false','').replace(', phase: phase, windowClosed: windowClosed','').replace(', windowClosed: windowClosed','');assert normal==(B/'Sources/FactoryProbe/MetricsLogging.swift').read_text()
viewport=(P/'package/Sources/FactoryProbe/FactoryViewport.swift').read_text();old=(B/'Sources/FactoryProbe/FactoryViewport.swift').read_text()
for guard in ['guard pid == pointer.pointee.pid, thread == pointer.pointee.thread else { return WindowsBool(true) }','guard count > 0, String(decoding: buffer.prefix(Int(count)), as: UTF16.self) == "Alchemist FactoryProbe" else { return WindowsBool(true) }','guard rc, lookup.matches == 1, let hwnd = lookup.hwnd,\n          expected == nil || expected == hwnd, IsWindow(hwnd) else {','throw NSError(domain: "FactoryOwnedRendererHWNDAmbiguous", code: 1)']:
 assert guard in old and guard in viewport
assert viewport.index('FACTORY_HWND_DIAGNOSTIC')<viewport.index('throw NSError(domain: "FactoryOwnedRendererHWNDAmbiguous"')
assert viewport[viewport.index('    var rectangle = RECT()'):]==old[old.index('    var rectangle = RECT()'):]
assert 'candidates.count < 64' in viewport and 'candidateOverflow = true' in viewport
runner=(P/'runner/capture-repeat.ps1').read_text();parent=R/m['runnerTemplate']['parent'];assert sha(parent)==m['runnerTemplate']['parentSha256']
base=parent.read_text()
for x in ["$exitDeadline=[DateTime]::UtcNow.AddSeconds(15)","while(-not $p.WaitForExit(100))",'if(-not $stdoutTask.Wait(5000) -or -not $stderrTask.Wait(5000))',"try{$cleanupResult=Invoke-FactoryOwnedCleanup $p $exe $ownedStartedAt -KnownStartedIdentity}",'Assert-FactoryCaptureOutcome $primaryError $cleanupResult $streamErrors']:
 assert x in base and x in runner
assert runner.count('$ownedKernelHandle=$p.Handle')==1
assert runner.index(' try {\n $ownedKernelHandle=$p.Handle')>runner.index('$p=[Diagnostics.Process]::Start')
assert "if([DateTime]::UtcNow -gt $exitDeadline){Write-OwnedExitSample $p $ownedKernelHandle 'original-15s-deadline' $dir $kernelSampleErrors;throw 'Owned renderer child deadline'}" in runner
assert 'WaitForSingleObject($Handle,0)' in runner and 'GetExitCodeProcess($Handle,[ref]$code)' in runner and 'GetProcessId($Handle)' in runner
assert '}catch{$Errors.Add([string]$_)}' in runner
assert runner.index("'before-original-cleanup' $dir")<runner.index('try{$cleanupResult=Invoke-FactoryOwnedCleanup')<runner.index("'after-original-cleanup' $dir")
plan=json.loads((P/'package/plan.json').read_text())
for row in plan['sourceBindings']:assert sha(P/'package'/row['path'])==row['sha256'].removeprefix('sha256:')
report={'verdict':'CLEAR_DIAGNOSTIC_SOURCE_ONLY','findings':[],'manifestSha256':sha(P/'source-manifest.json'),'planSha256':sha(P/'package/plan.json'),'runnerSha256':sha(P/'runner/capture-repeat.ps1'),'manifestRowsVerified':len(m['files']),'checks':['Original HWND enumeration acceptance, candidatecount/title/PID/thread/expectedHWND/IsWindow/readback/DPI/foreground guards unchanged; bounded64 diagnostic candidates do not cap original matchcount.','Failure-only receipt immediately before same NSError; phase &known-close flag diagnostic-only. No post-close suppression.','Main normalized delta equals metrics-v2; windowClosed flag only propagated to receipts. Witness/layout/measurement/fill/runtime/shared serializer unchanged.','One original Process.Handle captured inside existing try; zero-time before/after kernel waits bracket Framework.HasExited/GetExitCodeProcess with monotonic clocks plus handlePID; no reopening, reset or new cleanup decisions.','Original15s deadline established before sample; sample executes before unchanged deadline throw. Existing5s streams/cleanup/errorpriority retained. Sampling failures recorded separately.'], 'boundary':'Runner is source-only historical lifecycle template with historical stack admission routes. Requires fresh padding route/compile/host-validity bindings before any dispatch; no launch acceptance emitted. Diagnostic IO changes observational overhead without timing qualification.','reviewExecution':'Offline Python/source/hash only; zero native/compiler/remote actions','pins':{str(p.relative_to(R)):sha(p) for p in [P/'source-manifest.json',P/'package/plan.json',P/'runner/capture-repeat.ps1',P/'package/Sources/FactoryProbe/main.swift',P/'package/Sources/FactoryProbe/FactoryViewport.swift',P/'package/Sources/FactoryProbe/MetricsLogging.swift',parent]}}
(O/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(sha(O/'report.json'))
