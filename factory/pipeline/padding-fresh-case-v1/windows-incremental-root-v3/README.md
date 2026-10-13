# Padding cached incremental Windows compiler

This source packet prepares compile-only work for fresh Padding case `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9`. It consumes fresh `plan.json` plus `fresh-inputs/{case,manifest,tuple}.json`, verifies raw refs, parsed case/tuple/host joins, exact 13 source rows against donor source rows, bridge rows against explicit bridge root, & donor compile receipt/plan lineage. Source rows without `bytes` are measured; no row is trusted from claimed size. Existing operational package/cache are inputs only. Fresh output must be outside both.

Donor plan SHA is `ee83748cd42326e57676e47d8fec777bd8466706ba2c72a01eb9b5b71292de10`; donor receipt SHA is `1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf`. Donor argv is preserved verbatim from receipt, including GUI linker flags. Builder does not inject `-j` or `-Xswiftc -num-threads`, & reports frontend concurrency as unobserved. Job cap stays 1 GiB with flag 512, `killOnJobClose=false`; retained handle, bounded exit/drain, kernel exit, active-job zero, sealed output hashes & fresh output receipt follow proven incremental lifecycle. Preflight has `nativeActions=0`; final remains compile-only until root separately admits native capture.

Root must provide measured Dell paths. Read-only preflight command shape:

```powershell
& .\build-padding-incremental-v2.ps1 `
  -FreshPlanPath D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\package\plan.json `
  -FreshPlanSha256 <measured-fresh-plan-sha256> `
  -FreshInputRoot D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\package `
  -OperationalPackage D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package `
  -OperationalScratch D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\build-capture-lease-r1\scratch `
  -OperationalPlanPath <actual-donor-package-plan.json> `
  -OperationalPlanSha256 ee83748cd42326e57676e47d8fec777bd8466706ba2c72a01eb9b5b71292de10 `
  -OperationalReceiptPath <actual-build-r1\observation.json> `
  -OperationalReceiptSha256 1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf `
  -CompilerPath <measured-swift.exe> -RendererPath <measured-renderer.dll> `
  -JobHelperPath D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\inputs\Sr0OwnedJobProcess.cs `
  -BridgeRoot D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge `
  -OperationalExpectedOutputPath D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\build-capture-lease-r1\scratch\out\Products\Release-windows-x86_64\FactoryProbe.exe `
  -OutputRoot D:\Claude\swiftright\.factory-work\hosts\padding-fresh-r11-r3\incremental-root-r1 `
  -Phase preflight -PreflightOnly
```

Run controls first, with fresh `-ControlRoot` under rolling host work. Add `-OperationalExpectedOutputPath` to controls. Controls call same builder against positive input then wrong plan/source/case/tuple/host/receipt/cache/kind/cap mutations. They preserve failed fixtures & never delete. No qualification/parity claim is made by this packet.
