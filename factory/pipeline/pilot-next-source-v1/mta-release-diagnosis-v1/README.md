# MTA release diagnosis v1

Prospective release overlay for Count1-r9. Failed receipt stays immutable.

Observed failure: `actual-count1-r9-transport/transport.json.stderr.bin` reports `All owned worker original handle proofs required` from `coordinator-count1-v3.ps1`. Producer MTA invoker writes `factory-uia-snapshot-worker-config-v2` with `parentApartment`, `apartment=MTA`, & MTA source bindings. Existing release proof accepts only config kind `factory-uia-snapshot-worker-config-v1`, so worker original-handle proof returns false after renderer proof succeeds. This is schema mismatch, not evidence that worker exited or streams were invalid.

`final-exit-certificate-mta-v1.ps1` is copied from pinned producer support `final-exit-certificate.ps1`; only worker config admission is extended to exact v2 + `apartment=MTA` + observed parent apartment `STA|MTA`. Existing retained handle, terminal certificate, source-contract, config, raw-stream, hash, & original outcome checks remain active.

`all-owned-release-rectangle-mta-v1.ps1` preserves frozen release logic under new function `Assert-RootRectangleAllOwnedReleaseMta`. Stage MTA support overlay after producer UIA support so `Test-FactoryUiaFinalReleaseProof` resolves to MTA correction, then dot-source MTA release function. Call with same Directory/Owner/CompilePath/CompileHash/Exe/ExeHash/SourceHash/ProducerRoot/SourceInputs arguments. Do not rewrite failed r9 receipts.

Root must run source controls & actual release proof against archived r9 raw directory after raw export. No source packet claims native success or lock release.

`Test-FactoryUiaWorkerConfigAdmission` is shared by production proof & controls. It accepts legacy v1 unchanged; accepts v2 only with worker `MTA` & observed parent `STA|MTA`; rejects v2 `STA`, missing apartment, unknown version, & wrong output root. `test-mta-config-admission.ps1` exercises those cases through shared predicate. `invoke-mta-release-proof.ps1` is root's non-mutating entry after exact archived raw export.
