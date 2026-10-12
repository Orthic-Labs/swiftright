# Image resizable source hold

This packet binds existing `Image(systemName: "star.fill")` recipe to ABI 0.6 evidence. ABI 0.6 exposes retained RGBA registration/release only; it has no SF Symbol catalogue/provider. Existing FactoryProbe renderer has no `Image` node branch, & its default branch rejects unsupported nodes. Therefore no identical `star.fill` resolution or substitute RGBA asset is claimed.

Source evidence is hash-bound in `source-manifest.json`. `hold.json` records exact admission blocker. Native/compiler/remote/GUI/lock actions remain zero.

`witness-rgba.swift`, `image-asset.swift`, `image-render-branch.swift`, & `rgba-recipe.json` provide next admitted `swiftui.image.rgba-registered-v1` proposal: source-bound 4×4 RGBA bytes, deterministic nearest expansion to 32×32, ABI `Bridge.registerImage`/release, explicit `Primitive.image`, UIA/pixel receipts, & fresh tuple/case. This block remains separate from `systemName` semantics. Same-source Mac/Windows admission still requires each host to bind same asset bytes; existing Mac SwiftUI named-image loading is not treated as proof. SF Symbol pilot stays held until source-bound renderer/provider capability exposes symbol lookup plus measured glyph identity.

Root adaptation files: `Bridge.swift` & `swiftright.h` are protected ABI inputs; `FactoryProbe/main.swift` needs reviewed Image/provider support before any host packet can run. No edits are proposed here.
