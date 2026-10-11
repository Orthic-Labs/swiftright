# Final exit certificate v1

Source-only successor; no remote, compiler, GUI, process or lock execution performed for this packet. Pure controls are PREPARED/UNRUN. Original lifecycle cleanup258/15s deadline & historical recovery stay immutable.

Integration order:

1. Dot-source helper & call `Initialize-FactoryFinalExitNative` before renderer `Process.Start`. Immediately retain original `$p.Handle` once & record `start`: strict integer `pid`/`retainedHandle`, original `path`/`startedAt`, exact `lockOwner`/`workerId`, admitted `compileReceiptHash`/`exeHash`. Never reconstruct these from PID lookup or later Handle getter.
2. Keep original cleanup & primary deadline unchanged. After existing stream copy/flush/closure finishes, construct exactly stdout/stderr states using existing state fields plus `path` & actual `sha256` from existing gated hash function. No hash read while destination remains open.
3. Call `Get-FactoryFinalExitSample $originalHandle $start`; all kernel waits use 0ms. No .NET HasExited, kill, lookup, handle replacement, retry, blocking stream close or native wait is introduced. Type initialization is outside this final snapshot.
4. `New-FactoryFinalExitCertificate $sample $start $streams` rejects anything except same PID/handle, both kernel signals0, successful exit query !=259 & strict two sealed closed streams. Preserve as NEW `final-exit-certificate.json`; append reference/hash to NEW terminal worker receipt. Never overwrite original `cleanup`, `primaryError`, `exitCode`, `hostValid`, nativeParity or qualification.
5. Terminal worker receipt schema: `kind: factory-terminal-worker-v1`, typed `terminalResultConfirmed:true`, exact `start`, `finalCertificateRef`, `finalCertificateHash`. Writer emits only after final sampling/raw closure; original outcome remains separate. Coordinator reads hash-bound receipt & certificate bytes.
6. `Test-FactoryFinalReleaseProof(certificate, expected, reader)` validates exact admitted start/owner/compile/exe against coordinator's immutable context; reads exact worker, certificate, compile & executable bytes plus both raw stream bytes & recomputes hashes. Expected additionally supplies `workerReceiptRef/Hash`, `compileReceiptRef`, `exeRef`. Reader(ref) returns one `byte[]` object (PowerShell `return ,$bytes`), never caller pass labels; coordinator bounds its existing read operations.
7. `Invoke-FactoryFinalCertifiedRelease` invokes existing release callback with exact expected owner ONLY if proof verifies. Callback still checks original terminal task not Running & performs existing exclusive exact-owner lock CAS. Helper does not read/write desktop.lock itself. Foreign owner must never be released. Source proof does not replace coordinator terminal task checks.

Either original admitted cleanup certificate OR separate final certificate may authorize owner release after task termination. A final certificate after original15s/5s failures only fixes lock retention; original capture outcome stays failed. No semantic/native/parity/golden qualification changes.

Root command for pure controls after source review (no process/native/lock operations):

```powershell
powershell.exe -NoProfile -NonInteractive -File test-final-exit-certificate.ps1
```

20 isolated synthetic controls include exact original zero, missing kernel, HasExited-only, foreign owner, wrong handle/PID, missing/duplicate/open stream, typed boolean/wait faults, still-active/query failure, raw/compile/exe byte drift, nonterminal worker, missing reader reference, preserved failed outcome after release & callback refusal. Every mutated certificate is coherently rehashed into worker receipt.
