# Rounded stroke host package v1

Source packet targets exact current SwiftRight 37429120 runtime, owned SwiftRightBridge inputs & renderer:

- Runtime: `D:\Claude\swiftright\.factory-work\runtime-stage\runtime`
- Bridge: `D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge`
- Renderer: `D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll`

`Witness.swift` preserves original `RoundedRectangle(cornerRadius: 6).stroke(Color.blue, lineWidth: 2)` recipe. `FactoryShapePrimitive.swift` maps circular rounded geometry to ABI rect radius & maps fill/stroke fields to ABI rect fields. Continuous rounded stroke remains explicit provider hold; no flattening or substitution is accepted.

Root staging command:

```powershell
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke -PreflightOnly
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke
```

Root compile request command:

```powershell
& 'D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\tools\compile-bounded.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke
```

Request must run through root Windows Job Object adapter capped at 1 GiB, one SwiftPM job & one frontend thread. Exact SwiftPM argv is:

```text
swift build --package-path D:\Claude\swiftright\.factory-work\hosts\rounded-stroke\package --scratch-path D:\Claude\swiftright\.factory-work\hosts\rounded-stroke\package\build-bounded-r1\scratch --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release -Xlinker /MANIFEST:EMBED -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup
```

`plan.json` keeps `executionEligible:false`, `hostHash:null`, `caseHash:null`, & `outputs:null` until root records fresh compile/native receipts. Required holds: centered continuous rounded-stroke provider, fresh compile/native receipts & renderer sampling at host DPI.
