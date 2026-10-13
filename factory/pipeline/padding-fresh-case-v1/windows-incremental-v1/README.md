# Padding Windows incremental reuse

`build-padding-incremental-v1.ps1` is fresh-package-only. It verifies measured
 donor receipt `actual-build-r1/observation.json`, exact donor/fresh Swift rows,
 compiler/renderer/helper bytes & original GUI linker argv, then builds only from
 fresh `PlanPath`/`InputRoot`. Donor package/scratch remain read-only. Build receipt
 records original-handle job cap (1 GiB, `0x200`, kill-on-close false), one job,
 one frontend, sealed bounded streams, terminal exit & active-job zero. Fresh
 case/tuple/manifest evidence stays separately bound; donor receipt is lineage,
 not reused fresh execution evidence.

Root command, executed on Dell only after source review:

```powershell
& .\build-padding-incremental-v1.ps1 `
  -PlanPath 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\package\plan.json' `
  -InputRoot 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\package' `
  -DonorPlanPath 'D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\plan.json' `
  -DonorReceiptPath 'D:\Claude\swiftright\factory\native\windows\padding-capture-lease-build-v1\actual-build-r1\observation.json' `
  -DonorPackagePath 'D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package' `
  -DonorScratchPath 'D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\build-capture-lease-r1\scratch' `
  -CompilerPath 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe' `
  -RendererPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' `
  -JobHelperPath 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\inputs\Sr0OwnedJobProcess.cs' `
  -OutputRoot 'D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\incremental-build-r1' `
  -PreflightOnly
```

Remove `-PreflightOnly` only after root's serialized compiler approval. Fresh
scratch/output paths must be absent before invocation. Existing Swift source
must match donor rows byte-for-byte; fresh compiler receipt remains required.
