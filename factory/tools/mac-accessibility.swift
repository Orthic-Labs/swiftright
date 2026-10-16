// Read-only readback of the accessibility display flags and screens for the factory Mac jobs (no windows, no input).
import AppKit
let ws = NSWorkspace.shared
print("ax.reduceMotion=\(ws.accessibilityDisplayShouldReduceMotion)")
print("ax.reduceTransparency=\(ws.accessibilityDisplayShouldReduceTransparency)")
print("ax.increaseContrast=\(ws.accessibilityDisplayShouldIncreaseContrast)")
print("ax.differentiateWithoutColor=\(ws.accessibilityDisplayShouldDifferentiateWithoutColor)")
print("screens=\(NSScreen.screens.count)")
for s in NSScreen.screens {
    print("screen frame=\(Int(s.frame.width))x\(Int(s.frame.height)) backingScale=\(s.backingScaleFactor)")
}
