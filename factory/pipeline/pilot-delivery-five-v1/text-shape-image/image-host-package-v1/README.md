# Image host package v1

Source packet targets exact current SwiftRight 37429120 runtime, owned SwiftRightBridge inputs & renderer:

- Runtime: `D:\Claude\swiftright\.factory-work\runtime-stage\runtime`
- Bridge: `D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge`
- Renderer: `D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll`

`Witness.swift` uses named source-owned RGBA asset `factory.rgba.square.v1`; `FactoryRGBAImageRegistry.swift` registers one retained ABI image handle, reuses it per name, & releases it at window teardown. No SF Symbol or default asset substitution exists. Mac catalog PNG & Windows RGBA bytes derive from same 4x4 source payload.

Root staging command:

```powershell
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\image-host-package-v1\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host image -PreflightOnly
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\image-host-package-v1\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host image
```

Root compile request command:

```powershell
& 'D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\text-shape-image\image-host-package-v1\tools\compile-bounded.ps1' -Repo 'D:\Claude\swiftright' -Host image
```

Request must run through root Windows Job Object adapter capped at 1 GiB, one SwiftPM job & one frontend thread. Exact SwiftPM argv is:

```text
swift build --package-path D:\Claude\swiftright\.factory-work\hosts\image\package --scratch-path D:\Claude\swiftright\.factory-work\hosts\image\package\build-bounded-r1\scratch --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release -Xlinker /MANIFEST:EMBED -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup
```

`plan.json` keeps `executionEligible:false`, `hostHash:null`, `caseHash:null`, & `outputs:null` until root records fresh compile/native receipts. Required holds: same-source Mac/Windows capture, renderer sampling at host DPI & image-handle receipt.
