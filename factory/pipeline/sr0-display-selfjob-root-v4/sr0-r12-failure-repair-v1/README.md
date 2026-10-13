# SR0 r12 failure repair v1

Source-only successor for `root-native-r12-observer-r13-r1` failure. Raw evidence remains immutable under `native-r10c-recovery-v1/root-native-r12-observer-r13-r1/actual-failure`.

Observed failure is strict and retained: collector exited 1 after owned task handle terminal with raw/.NET exit 0, `workloadTargetPid=null`, workload stdout/stderr 0 bytes, `workload exit row count mismatch: 0 vs 1`; coordinator and launcher retained terminal/self-only proofs but no qualification certificate. Empty redirected streams do not establish workload identity. No row guard or display threshold is weakened.

`materialize-task-v9.ps1` is preferred: it copies exact staged `task-workload-v8.ps1` into fresh output, verifies four unique markers, & inserts flushes immediately after retaining child handle, after start identity, after kernel/.NET exit identity, & after stream-drain diagnostics. This preserves all current v8 fixes while preventing later non-terminating harness work from erasing owned lifecycle rows; missing rows still fail strict parser. `task-workload-v9-failure-publication.ps1` records same bounded donor correction for review.

`r12-failure-admission-v1.ps1` is pure production predicate. It admits only early transport hold when collector failure, coordinator original parent kernel terminal identity, launcher child terminal identities, aggregate descendants quiesced, aggregate active count 1/self-only, no cap violation, & no termination are all present. It always emits `qualificationClaim=false`, `lockReleaseEligibility=false`, & never fabricates workload PID/rows/certificate.

`observer-early-failure-v1.ps1` reads explicit sealed receipts with 1 MiB/file bounds, publishes atomic held verdict, & exits 0 only for `early-failure-held` (17 for rejection). It avoids waiting through full 1100-second observer budget after strict failed child receipts. Transport cleanup proof is separate from qualification & CAS release.

Root invocation after staging source pins:

```powershell
& .\materialize-task-v9.ps1 -SourcePath '<staged>\task-workload-v8.ps1' -OutputPath '<fresh-stage>\task-workload-v9.ps1'

& .\observer-early-failure-v1.ps1 `
  -CollectorPath '<actual-failure>\collector.json' `
  -CoordinatorPath '<actual-failure>\coordinator.json' `
  -LauncherPath '<actual-failure>\launcher.json' `
  -TaskName 'SR0-factory-display-selfjob-v7-root-r12' `
  -OutputPath '<fresh-run-root>\r12-failure-held.json'
```

Controls use same predicate:

```powershell
& .\test-r12-failure-admission-v1.ps1 -FailureRoot '<actual-failure>' -ControlRoot '<fresh-control-root>'
```
