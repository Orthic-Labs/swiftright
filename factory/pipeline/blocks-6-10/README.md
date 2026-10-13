# Blocks 6-10 cases (SR1)

One case = `package/` (Windows: Witness.swift + main.swift/FactoryViewport.swift/Package.swift stamped from `../pilot-delivery-five-v1/shared-windows-host/`) + `mac-source/` (byte-identical Witness.swift + the capture host from `MacHost.template.swift`).
`new-case.py <block/case> <Witness.swift> '<Witness_x()>'` creates both sides and stamps the host. Run with `python3 factory/tools/pair.py <case> --runs N --stage <stage> --renderer <0.7 dll> --sandbox`.

The Mac host draws an `NSHostingView` in a never-shown borderless window with `cacheDisplay` into an 800x600 bitmap (320x240 pt at 2.5). `ImageRenderer` is not used: it renders `ScrollView` content blank.
Keep the centred root on whole device pixels (width and height such that `(320 - w) * 1.25` and `(240 - h) * 1.25` are integers): SwiftUI does not snap a half-pixel origin, the runtime does.

## Animation cases (F1, manual clock; blocks 18 and 19)

`new-case.py <block/case> <Witness.swift> 'Witness_x()' --clock 0,0.25,0.5,...` creates a case with the clock host (`MacClockHost.template.swift`) and writes `pair.json` `"clock"`. The witness builds animations through `FactoryAnim.wrap(_:)` and timed events through `FactoryClock.at(t) { ... }`; both hosts define them (Windows: the animation as written; Mac: the original SwiftUI `Animation` evaluated at the manual clock). `pair.py` captures one pair per clock step per run (`native-NN-fKK.png` / `run-NN-fKK.png`, `HOST_GEOMETRY` in `windows/host-NN-fKK.stdout.txt`, `MAC_FRAME` in `mac-run-NN.log`). `pair.json` `"clockGate"` (see `factory/tools/pair_clock_report.py`) names the tracked shapes; a fractional animating edge is gated by extent (1 px) and exact pixels outside edge strips, other cases by exact pixels. Keep animating edges on the leading side of a fixed field and the clock at multiples that put them on whole device pixels where you can: then the frame is fully exact.
