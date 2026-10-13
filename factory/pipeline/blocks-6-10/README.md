# Blocks 6-10 cases (SR1)

One case = `package/` (Windows: Witness.swift + main.swift/FactoryViewport.swift/Package.swift stamped from `../pilot-delivery-five-v1/shared-windows-host/`) + `mac-source/` (byte-identical Witness.swift + the capture host from `MacHost.template.swift`).
`new-case.py <block/case> <Witness.swift> '<Witness_x()>'` creates both sides and stamps the host. Run with `python3 factory/tools/pair.py <case> --runs N --stage <stage> --renderer <0.7 dll> --sandbox`.

The Mac host draws an `NSHostingView` in a never-shown borderless window with `cacheDisplay` into an 800x600 bitmap (320x240 pt at 2.5). `ImageRenderer` is not used: it renders `ScrollView` content blank.
Keep the centred root on whole device pixels (width and height such that `(320 - w) * 1.25` and `(240 - h) * 1.25` are integers): SwiftUI does not snap a half-pixel origin, the runtime does.
