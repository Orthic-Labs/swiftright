// Read-only readback of the accessibility display flags and screens for the factory Mac jobs (no windows, no input).
import AppKit
let ws = NSWorkspace.shared
print("ax.reduceMotion=\(ws.accessibilityDisplayShouldReduceMotion)")
print("ax.reduceTransparency=\(ws.accessibilityDisplayShouldReduceTransparency)")
print("ax.increaseContrast=\(ws.accessibilityDisplayShouldIncreaseContrast)")
print("ax.differentiateWithoutColor=\(ws.accessibilityDisplayShouldDifferentiateWithoutColor)")
// The effective scroller style: legacy scrollers reserve a gutter at a List's trailing edge when its rows overflow (H21); overlay scrollers take no space.
print("ax.scrollerStyle=\(NSScroller.preferredScrollerStyle == .legacy ? "legacy" : "overlay")")
print("screens=\(NSScreen.screens.count)")
for s in NSScreen.screens {
    print("screen frame=\(Int(s.frame.width))x\(Int(s.frame.height)) backingScale=\(s.backingScaleFactor)")
}
