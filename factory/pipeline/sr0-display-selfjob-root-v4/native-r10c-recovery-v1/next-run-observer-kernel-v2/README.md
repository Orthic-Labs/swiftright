# Observer kernel v2

`observer-source-r12.ps1` is prospective only. It keeps admitted r11 plan, 32 source rows, 900-second workload deadline, one-second poll, 1 GiB job bound, `NoActivate`, `NoResources`, & `nativeActions=0` unchanged.

Schedule completion is governed by retained native process handle through `Sr0RootControlSuiteJobV1.Terminal` & `SignedDword`. `.NET HasExited`/`ExitCode` values are diagnostics only. Native wait states are explicit: cached false stays pending, native 258 stays pending, native 0 is terminal success, native error is held. Finally rechecks native terminal state before cleanup; it never substitutes `.NET` state.

After schedule streams seal, observer reads three bounded receipts. Passed proof follows existing r11 checks. Failed or held collector/coordinator/launcher receipts exit early as `held` only when coordinator parent certificate+kernel terminal, collector original handle+active self-only+sealed streams, & launcher aggregate quiescence+self-only all exist. Incomplete proof continues until bounded deadline, preserving held failure. No lock release is performed by observer.

Controls extract same production policy functions from observer source. Root may run after source pin admission:

```powershell
& .\test-observer-kernel-policy-r12.ps1 -ObserverPath .\observer-source-r12.ps1
```

Root must hash fresh source, stage source controls, invoke observer under existing admitted r11 plan/controls, & retain raw receipt on any held result. No qualification claim is emitted.
