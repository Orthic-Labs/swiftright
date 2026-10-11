# V4 source review

V4 receives source clearance for root controls. Its only functional delta is JSON-array shape handling after the v3 Windows PowerShell 5.1 failure: each consumer first assigns `ConvertFrom-Json` output to a variable, then enumerates that variable with `@($decoded)`. The three changed locations cover production parse admission, positive fixture projection, and parser-fault mutation.

`control-admission.ps1` now reaches `GetFullPath` once per parse row. `run-controls.ps1` performs actual root admission before fixture mutation; positive fixtures only require cleanup, host-input, and parse outputs, while integer/lint/admission proof remains root-only. V3 source and raw failure references remain preserved through `preserved-v3-reference-list.json`.

Reviewed stage: `49663c0438195fe7633cfb69773224a5cbd77289cf08d70fc696493f5bd77479`. Builder: `b82f4b071020877c3e307c768c56195f6ce1f6a56b61a6e4a03630a67936badf`; admission: `3691bca9bc9245f53f89b0368fdb607ab0a4f9f8724c1bf8a1bc417e3470962f`; controls: `087f42699071b5d7a15d182b6806a61d88a17315ff9f79af625fff14016143e9`.

No compiler, native, SSH, or GUI action occurred during this review. Root may run fresh bounded PowerShell controls, preserve receipts, and proceed to compiler gate only after controls pass.
