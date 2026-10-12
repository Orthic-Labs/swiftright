# Windows star.fill live-provider source packet v7

Fresh source packet cloned from v6. Original `Image(systemName: "star.fill")` body remains byte-preserved; Segoe Fluent Icons E735 remains explicit substitute provider with no SF Symbol parity claim. v6 remains immutable.

`FactorySystemImageRegistry.swift` fixes only invalid escaped interpolation quotes at provider/frame diagnostics. Windows & Mac `Witness.swift` are byte-identical (`sha256:0862162052b143a52e3f556e41f70fa02612b0b3f6ee83d7f7aecd835f6a018b`) and use conditional `SwiftRightRuntime`/`SwiftUI` imports only; witness body is unchanged. Mac source is under `mac-source/` for fresh same-source reference capture.

Runtime keeps live provider registration, target sizing, yellow tint, ABI 0.6 image-handle retain/release, and no cached RGBA or switch proxy. Root stages v7 under `system-star-fill-provider-bound-r7-v7`, then owns bounded compile & native observation.
