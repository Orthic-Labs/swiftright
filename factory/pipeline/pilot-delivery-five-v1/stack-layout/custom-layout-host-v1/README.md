# Custom Layout lifecycle host v1

Source-only Windows package derived from measured `stack-lifecycle-next-build-v1` host. Witness now uses current `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b` `LayoutSize`, `LayoutRect`, `LayoutPoint`, `Subview.sizeThatFits`, `Subview.place` APIs. Runtime `LayoutRoot`/`LayoutEngine` resolves placement; `main.swift` joins `ResolvedNode` bounds to existing ABI0.6 `Color` fill mapping, with explicit `Layout` child/bounds guards.

Package input: `D:\Claude\swiftright\.factory-work\hosts\custom-layout-lifecycle\package`.

Same-source Mac packet: `mac-source/`. It aliases current witness geometry to Apple Layout types, fixes host at 320x240 points, exposes only no-prompt `--preflight`/`--observe`, writes internal `/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/custom-layout-r1/` scratch, & records rootRSS before/after render. No Mac EXE or hash is claimed before root build.

Plan SHA256: `766a4c57988bd1a2a9dae0ae5f951bfd77e3404309e89eac53b3ed70d72c2e97`.

Runtime API pins: `Layout.swift` `229baee2f56f649ab93de9800119a86da4e5d03cd41a2227c60309e1131cb990`; `LayoutEngine.swift` `1322f549d76a5902a185cfd880f3e8c6d5f074785420ae9629d0f088bd69fa98`; `Graph.swift` `c81543a78ab0516df42a22947ae9f66a1d2635e961d0a5c0706a48924ad1f91f`; `Geometry.swift` `acc003c678fd38f9a89a3af299e1450be19561e0935731f9961afbbedf585b6e`.

Run source planner from Windows root with fresh paths:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\factory\pipeline\pilot-delivery-five-v1\stack-layout\custom-layout-host-v1\prepare-custom-layout-host.ps1" -RunRoot "D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\stack-layout\custom-layout-host-v1\native\custom-layout-prebuild-r1" -PlanOutput "D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\stack-layout\custom-layout-host-v1\native\custom-layout-prebuild-r1\plan.json"
```

Planner starts no compiler/native/lock. Root must stage package at canonical input path, run bounded GUI release compile from emitted `compileRequest.argv`, retain compile receipt & produced EXE, then perform Count1 capture with existing 15s child, 5s stream, 5s destination closure, retained-handle `FactoryProcessWaitV6` controls. No EXE/receipt/native hash is claimed here.
