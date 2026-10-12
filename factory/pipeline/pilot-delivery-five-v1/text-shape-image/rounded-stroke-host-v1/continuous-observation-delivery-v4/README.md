# Rounded stroke continuous observation delivery v3

Fresh source packet preserves exact original RoundedRectangle witness, light theme & current ABI 0.6 bindings. Current runtime `.continuous` style is mapped to existing ABI rect radius/border fields for observation only; requested style & dynamic radius/scale/stroke data are logged, with no continuous-semantics or parity claim. `FactoryCenteredLayout.swift` translates every resolved node in intrinsic root subtree by one viewport-centered delta; background remains unchanged. This fixes host placement without hardcoded leaf coordinates.

Canonical inputs:

- Runtime: `D:\Claude\swiftright\.factory-work\runtime-stage\runtime`
- Bridge: `D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge`
- Renderer: `D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll`

Root staging, source-only preflight, then stage copy:

```powershell
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\continuous-observation-delivery-v4\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-observation-v4 -PreflightOnly
& '.\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\continuous-observation-delivery-v4\tools\prepare-bounded-stage.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-observation-v4
```

Compile request (root Job Object, 1 GiB, one SwiftPM job, one frontend thread):

```powershell
& 'D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\text-shape-image\rounded-stroke-host-v1\continuous-observation-delivery-v4\tools\compile-bounded.ps1' -Repo 'D:\Claude\swiftright' -Host rounded-stroke-observation-v4
```

No compile, native capture, host hash or parity output is present in this packet. This is an observation-only approximation packet; root must report actual pixel diff bbox before any parity decision. Case is pinned to current materialized case hash `sha256:3d4ff2bb17d444335cdf55a9cc410665bf77b5574f4beed57764f0f6ad2cf71e`; root must archive fresh prebuild/final receipts before eligibility.


Stroke correction v4 expands ABI border bounds by half scaled line width and increases radius by same offset, matching centered-stroke extent from resolved geometry. Continuous corner construction remains observation-only and must be measured by root.
