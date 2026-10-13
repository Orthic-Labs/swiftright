# Continuous geometry path probe

Windowless macOS source probe only. It imports Foundation + SwiftUI, calls public `RoundedRectangle.path(in:)` for eight bounded geometry controls under `.continuous` & `.circular` (including zero/large radius, translation, & square-close controls), then emits one sorted JSON record per path through `Path.forEach`. Output is capped below 60 KiB per record & in total, with 16-record hard cap. No renderer, window, AX, capture, permissions, or Windows inputs.

Root may copy this source to internal-disk scratch & compile/run under existing macOS lifecycle controls. Preserve emitted JSON with source/compiler receipt. Probe output describes public path elements; it is evidence for geometry transport, not pixel parity.
