# Fresh Padding Windows capture packet v4

`stage-padding-capture-v4.py` is source-only Windows staging. It copies explicit donor producer closure, binds fresh case/manifest/nested `tuple.id`, measured plan, separate measured receipt, exact operational package, exact operational executable, serializer, & preflight. It performs no compiler, native, scheduler, desktop-lock, or process action.

Root runs on Windows with explicit staged case/manifest/tuple paths. Measured plan & receipt are separate refs:

```powershell
py -3 .\stage-padding-capture-v4.py `
  --donor-root D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v1 `
  --case D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\fresh-inputs\case.json `
  --manifest D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\fresh-inputs\manifest.json `
  --tuple D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\fresh-inputs\tuple.json `
  --recipe D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\fresh-inputs\recipe.json `
  --source D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\fresh-inputs\source.swift `
  --compile-plan D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\plan.json `
  --compile-receipt D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\incremental-v4-final-r2\observation.json `
  --operational-package D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package `
  --operational-exe <exact-exePath-from-observation.json> `
  --preflight D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\preflight.ps1 `
  --serializer-control D:\Claude\swiftright\.factory-work\root-tools\padding-incremental-v4-r2\serializer-control.json `
  --output D:\Claude\swiftright\.factory-work\padding-fresh-v4-count1 `
  --windows-stage-root D:\Claude\swiftright\.factory-work\padding-fresh-v4-count1 `
  --count 1
```

Root must replace only paths marked by measured Windows packet when receipt gives different executable path. Operational package guard requires exact receipt `operationalPackage`; executable guard requires exact receipt `exePath` & hash. No nonempty-path fallback exists.

Output uses proven `factory-padding-source-inputs-v2` consumer kind, `factory-source-bound-candidate-binding-v1`, & frozen Count1/Count20 controllers. `metadata/source-inputs.json` carries staged Windows refs for case, manifest, tuple, recipe, source, serializer, binding, plan, & receipt. `compilePlanPath` & `compileReceiptPath` retain separate measured refs. Producer `capture-plan.json` uses capture-plan-v1 scaffold kind plus explicit `compilePlanPath`/`compileReceiptPath`.

Post-patch resealing occurs for producer integration bindings & producer root-stage manifest. `nativeActions`, `compilerActions`, & `lockActions` remain zero. Count20 remains blocked until fresh Count1 proof.
