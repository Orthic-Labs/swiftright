# SR0 failed observer held predicate controls v2

Controls hash-pin r13 observer source, parse it, & AST-extract only production `Test-FailedQuiescentReceipts`. No observer body, scheduler, native action, or receipt writer executes.

Archived r12 failure receipts must be accepted by extracted production predicate. Faults must reject missing original retained parent handle, PresentMon terminal false, aggregate active count two, launcher exit identity false, wrong status, missing parent kernel proof, & parent raw/signed/.NET mismatch.

```powershell
& .\test-held-predicate-v13.ps1 `
  -FailureRoot '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\root-native-r12-observer-r13-r1\actual-failure' `
  -ObserverPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\root-source-admission-r13-v1\observer-source-r13.ps1' `
  -SourcePinsPath '.\source-pins.json' -ControlRoot '<fresh-control-root>'
```

No qualification claim or lock release is emitted.
