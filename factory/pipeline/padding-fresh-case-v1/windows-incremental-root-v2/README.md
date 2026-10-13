# Padding cached incremental Windows compiler

This source packet prepares compile-only work for fresh Padding case `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9`. It consumes fresh `plan.json` plus `fresh-inputs/{case,manifest,tuple}.json`, verifies their raw hashes, measures source rows against operational package, verifies bridge rows against explicit bridge root, & checks donor compile receipt/plan lineage. Source rows without `bytes` are measured; no row is trusted from a claimed size. Existing operational package/cache are inputs only. Fresh output must be outside both.

Donor argv is preserved from actual successful compile receipt, including GUI linker flags. Builder does not inject `-j` or `-Xswiftc -num-threads`; fresh plan records those fields for policy review, while donor cached argv remains source of operational command. Job cap stays 1 GiB with flag 512, `killOnJobClose=false`; retained handle, suspended assignment, stream drain, kernel exit, active-job zero, sealed output hashes & fresh output receipt follow proven incremental lifecycle. Preflight has `nativeActions=0`; final remains compile-only until root separately admits native capture.

Root must provide measured Dell paths. Read-only preflight command shape:

```powershell
& .\build-padding-incremental-v1.ps1 `
  -FreshPlanPath D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\package\plan.json `
  -FreshPlanSha256 <measured-fresh-plan-sha256> `
  -FreshInputRoot D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\package `
  -OperationalPackage D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package `
  -OperationalScratch D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\build-capture-lease-r1\scratch `
  -OperationalPlanPath <actual-donor-package-plan.json> `
  -OperationalReceiptPath <actual-build-r1\observation.json> `
  -CompilerPath <measured-swift.exe> -RendererPath <measured-renderer.dll> `
  -JobHelperPath D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\inputs\Sr0OwnedJobProcess.cs `
  -BridgeRoot D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge `
  -OutputRoot D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\incremental-root-r1 `
  -Phase preflight -PreflightOnly
```

Run controls first, with a fresh `-ControlRoot` under rolling host work. Controls call same builder preflight against positive input then wrong plan/source/case/host/cache/kind/cap mutations. They preserve failed fixtures for review & never delete. No qualification/parity claim is made by this packet.
