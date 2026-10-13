# Rounded stroke centered delivery v1

Fresh source packet preserves exact RoundedRectangle witness, light theme & current ABI 0.6 bindings. `FactoryCenteredLayout.swift` translates every resolved node in intrinsic root subtree by one viewport-centered delta; background remains unchanged. This fixes host placement without hardcoded leaf coordinates.

Canonical inputs:

- Runtime: `D:\Claude\swiftright\.factory-work\runtime-stage\runtime`
- Bridge: `D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge`
- Renderer: `D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll`

Root staging, source-only preflight, then stage copy:

```powershell
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\centered-delivery-v1\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-centered -PreflightOnly
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\centered-delivery-v1\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-centered
```

Compile request (root Job Object, 1 GiB, one SwiftPM job, one frontend thread):

```powershell
& 'D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\centered-delivery-v1\tools\compile-bounded.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-centered
```

No compile, native capture, host hash, case hash or parity output is present in this packet. Root must archive fresh prebuild/final receipts before eligibility.
