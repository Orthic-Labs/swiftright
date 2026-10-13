# Rectangle centered-root adapter v3

Paired evidence showed exact 40x20 Rectangle at Windows `[0,0]` while Mac placed it at `[140,110]` in 320x240. Existing direct-child centering can miss primitive after `.fill`, `.frame`, `.environment`, witness, & root wrappers.

`FactoryCenteredLayout.swift` computes one translation from resolved `root.pixelFrame` plus current owned viewport: `viewport origin + (viewport size - intrinsic root size)/2 - root origin`. Fresh host applies same translation to every `ResolvedNode` in root subtree, including wrapper, modifier, shape, & descendants. Background node remains unchanged. No leaf kind, case coordinate, or hardcoded 140/110 is used. Nonfinite or non-fitting roots fail closed.

Apply `main.patch` to root's current `commit` walk in `rectangle-color-capture-r5/actual-native-r3/files/native/count1-r1/Sources/FactoryProbe/main.swift`. Add `FactoryCenteredLayout.swift` to same `Sources/FactoryProbe` target. Root owns bounded compile/capture & receipts; historical plans/EXEs stay untouched.

Expected fresh placement target for 320x240, 40x20 intrinsic root is `[140,110]`; source packet has no measured result.
