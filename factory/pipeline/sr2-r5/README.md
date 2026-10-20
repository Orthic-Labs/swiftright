# SR2 R5: text (issue #40)

- **digits-view-modifier-v1:** a copy of `blocks-w1-f2/swiftui.system-font-f2/digits-v1`, with its two tabular rows set through the View-level `.monospacedDigit()` instead of `Font.monospacedDigit()`. SwiftUI draws both forms the same way, so the case keeps that case's calibrated text regions (decision G71).
- **minimumScaleFactor:** unit tests only (`TextScalingTests`). SwiftUI shrinks to a continuous size, while the runtime floors to the half-point steps of the measurer's metric table, so the result can be up to 0.5 pt smaller and a pixel gate would only measure that known difference. In the Pulse notch it is a safety net: the ring's percentage sits in a frame measured to fit.
