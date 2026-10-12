# Rounded stroke circular-centered delivery v2

Fresh source packet preserves exact circular-style RoundedRectangle witness, light theme & current ABI 0.6 bindings. Startup provider hold is removed because runtime default style is circular; explicit `.continuous` remains rejected by shape mapper. `FactoryCenteredLayout.swift` translates every resolved node in intrinsic root subtree by one viewport-centered delta; background remains unchanged. This fixes host placement without hardcoded leaf coordinates.

Canonical inputs:

- Runtime: `D:\Claude\swiftright\.factory-work\runtime-stage\runtime`
- Bridge: `D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge`
- Renderer: `D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll`

Root staging, source-only preflight, then stage copy:

```powershell
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\circular-centered-delivery-v2\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-circular -PreflightOnly
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\circular-centered-delivery-v2\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-circular
```

Compile request (root Job Object, 1 GiB, one SwiftPM job, one frontend thread):

```powershell
& 'D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\circular-centered-delivery-v2\tools\compile-bounded.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-circular
```

No compile, native capture, host hash or parity output is present in this packet. Case is pinned to current materialized case hash `sha256:3d4ff2bb17d444335cdf55a9cc410665bf77b5574f4beed57764f0f6ad2cf71e`; root must archive fresh prebuild/final receipts before eligibility.
