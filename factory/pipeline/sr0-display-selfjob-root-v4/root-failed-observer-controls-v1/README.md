# SR0 failed observer held predicate controls v1

Controls pin r12 archived failure receipts & fresh r13 observer source. Actual fixture is collector `failed`, coordinator `held`, launcher `held`; original handles are retained, kernel exits are terminal, aggregate active count is one, & no qualification claim is emitted.

`Test-HeldPredicateV13` accepts only this transport-held state. Faults reject missing original retained handle, aggregate active count two, mismatched coordinator raw/signed/.NET exit identity, wrong status, & missing parent kernel proof. Positive qualification predicates remain untouched.

Pinned receipt hashes come from archived `actual-failure/export-verification.json`; observer SHA is from r13 source metadata.

```powershell
& .\test-held-predicate-v13.ps1 `
  -FailureRoot '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\root-native-r12-observer-r13-r1\actual-failure' `
  -ObserverPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\root-source-admission-r13-v1\observer-source-r13.ps1' `
  -SourcePinsPath '.\source-pins.json' -ControlRoot '<fresh-control-root>'
```

No native action, lock release, or qualification action occurs.
