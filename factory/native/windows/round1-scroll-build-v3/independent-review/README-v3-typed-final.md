# V3 typed-admission final source review

Source review clears current r3 for root Windows PowerShell controls. `run-controls.ps1` now invokes each control script through separate paths. `Test-ControlIntegerEqual` accepts only Int32/Int64 values in `0...Int32.MaxValue` with exact expected value, rejecting bool, floating/decimal, negative, out-of-range, string, null, and array inputs.

Current stage is pinned by r3 manifest `9911b0a0211226f0d4bbbf60b8aebe183fb2f0150ec763d1accb8eb0bfcc1d7f`; r2 files and pre-repair snapshots remain retained. Root runs controls under Windows PowerShell 5.1, archives receipts, then decides compiler entry. This reviewer performed no execution.
