# Rectangle host fix v1 — prospective build input

This packet is source-only. It changes one host palette entry in `FactoryFill.swift`:
`system.red` changes from `0xff3b30ff` (observed Windows `[255,59,48,255]`) to `0xff383cff` (Mac paired `[255,56,60,255]`). Geometry, RGBA validation, `Witness.swift`, recipe acceptance, runtime `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, & renderer `e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93` remain pinned. No native parity or corrected EXE claim is made here.

Files:

- `FactoryFill.swift`: explicit prospective replacement; measured SHA256 `21da245416c4bc6bd04981269546236e2a4c9d06dea4ecf2bd0664bf4dccf96f`.
- `Witness.swift`: exact original Rectangle witness; measured SHA256 `5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d`.
- `case-prospective.json`: exact case, recipe, & witness pins.
- `tuple-prospective.json`: exact runtime/renderer tuple basis; corrected Windows host, tuple/binding, compile, EXE, & native fields are pending.
- `plan-prospective.json`: source-binding delta & exact compiler inputs; `expectedHostHash`, receipt, EXE, plan, tuple, binding, & measured fields are pending.

## Proven build basis

Closest final plan: `factory/native/windows/pilot-rectangle-fixed-root-v2/plan-final-v4.json`, SHA256 `980b212bbdbda14623cfa6cde416c0af959246c574bbb3074599b9959d2991a8`.

Closest final compile receipt: `factory/native/windows/pilot-rectangle-fixed-root-v2/actual-final-r2/final-r2/observation.json`, SHA256 `21b08f393d3c1bc9650b960a5b32aea01be826c704ebf7b8cb52e1d62d32cd0c`. It is old-host evidence only: exit `0`, old EXE SHA256 `62aa7d5b9a5b9001d697822d26b2d102d8934de1de4a02103f810e756f71af66`; do not reuse corrected-host outputs.

## Root staging & invocation

1. In fresh root-owned `D:\Claude\swiftright\.factory-work\hosts\rectangle\package`, retain every unchanged source binding from proven `plan-final-v4.json`; replace only `Sources/FactoryProbe/FactoryFill.swift` with this packet file & retain exact `Sources/FactoryProbe/Witness.swift`.
2. Carry `runtime-source-receipt.json`, `runtime-source-tree.json`, `witness.manifest.json`, Package.swift, bridge/runtime roots, helper, & renderer through existing bounded compiler/rolling-cache adapter. Do not create a new compiler or renderer path.
3. Derive a fresh full `factory-rectangle-compiler-plan-v2` from `plan-final-v4.json`; update FactoryFill binding, leave `sourceHash` bound to exact Witness, set fresh `planSha256`, & leave corrected `expectedHostHash` pending until build. Stage it as `D:\Claude\swiftright\.factory-work\hosts\rectangle\package\plan-final-v4.json`.
4. Reuse existing guarded script `factory/native/windows/pilot-rectangle-fixed-root-v2/build-owned-v4.ps1` with fresh measured plan SHA (single compile job, release, `build-bound-r1\scratch`):

```powershell
& 'D:\Claude\swiftright\factory\native\windows\pilot-rectangle-fixed-root-v2\build-owned-v4.ps1' `
  -PlanPath 'D:\Claude\swiftright\.factory-work\hosts\rectangle\package\plan-final-v4.json' `
  -PlanSha256 '<fresh measured 64-hex plan SHA256>' -Phase final -Attempt <fresh attempt>
```

Existing wrapper `factory/native/windows/pilot-rectangle-fixed-root-v2/compile-final-v4.ps1` shows same staging/invocation shape, but its old plan pin must not be reused. Root then owns 20-row Windows capture & all measured receipt/tuple/binding updates under native hold.

Required channels remain `layout` plus original acceptance; `provider.paint`, `native.screenshot`, & `native.uia` stay unavailable until coordinated native capture. Native parity stays hold until root’s fresh 20-row run.
