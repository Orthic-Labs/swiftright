# Text baseline Windows source adapter

Source-only adapter contract for `swiftui.text.layout.baseline.pilot-next`. Root may reuse reviewed Rectangle Count1/Count20 lifecycle scripts only after staging this packet's fresh source inputs & integration guard. Adapter must bind exact `Text("Aa")`, system regular 24pt font, primary color, light scheme, 120x48 centered viewport, measured runtime commit, renderer hash, compile receipt, tuple, case, serializer, & host executable.

Windows capture keeps background placement, targeted UIA, compositor pixels, retained renderer handle, worker/renderer terminal proof, sealed streams, 1GiB self-job, CAS lock, & original owned handles. It must retain complete raw UIA trees even when `AXStaticText` or text extraction is unavailable. Font family resolution, effective scale, viewport, baseline, & fallback family are measured fields; inferred values are rejected.

Count1 precedes Count20. Fresh prefixed capture/image IDs, source/case/tuple/compile/runtime/renderer/font/viewport joins, & exact raw archive hashes are required. No Rectangle or padding metadata satisfies this contract.

Runnable compiler source is `compile-text-host.ps1`. Root stages fresh `D:\Claude\swiftright\.factory-work\hosts\text-baseline\package`, `plan-prebuild.json`, `plan-final.json`, runtime/bridge closures, & exact audited `Sr0OwnedJobProcess.cs`; then runs:

`stage_text_windows_package.py` is bounded source-only package materializer. It accepts only explicit rows from reviewed Rectangle `stage-manifest.json`, verifies each row before streaming copy, replaces only `Witness.swift` & three exact Text host sites, then emits `text-package-source-manifest.json`. It never discovers files recursively, invokes Swift, or edits donor package. Windows compile must stage exact audited `Sr0OwnedJobProcess.cs` (13575 bytes, `sha256:112e5775dc01282b0938dada7b9cec20412f82744257177f0a7846c2a723c69e`), which exposes suspended-process APIs required by `compile-text-host.ps1`; historical `Sr0OwnedJobProcess-v15.cs` self-job helper is not execution input. `test-owned-helper-api.py` performs bounded source/API/hash admission & records zero native/compiler actions.

```powershell
& python .\stage_text_windows_package.py --base-package D:\Claude\swiftright\factory\native\windows\pilot-rectangle-root-v1\package --base-manifest D:\Claude\swiftright\factory\native\windows\pilot-rectangle-root-v1\stage-manifest.json --output D:\Claude\swiftright\.factory-work\hosts\text-baseline\package --witness D:\Claude\swiftright\factory\pipeline\pilot-next-source-v1\text-baseline-v1\witness.swift
```

Generate each plan from measured closure rows with `prepare_text_windows_plan.py`; use `--phase final --case <generated-manifest.json> --expected-host-hash sha256:<64-hex>` only after prebuild output is measured.

```powershell
& .\compile-text-host.ps1 -PlanPath D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\plan-prebuild.json -PlanSha256 <measured-plan-sha256> -Phase prebuild
& .\compile-text-host.ps1 -PlanPath D:\Claude\swiftright\.factory-work\hosts\text-baseline\package\plan-final.json -PlanSha256 <measured-plan-sha256> -Phase final
```

Plans must carry `factory-text-compiler-plan-v1`, `swiftui.text.layout.baseline.pilot-next`, runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`, system regular 24/default font, & 120×48 center viewport. Compiler receipt & executable hashes remain measured inputs.
