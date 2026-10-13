import Foundation
import SwiftRightRuntime

// Factory host adapter: apply root center alignment to direct primitive child.
// Runtime, renderer, recipe, & historical plans remain untouched.
func factoryCenteredRootChild(_ bounds: Rect, viewport: Rect, directChildOfRoot: Bool) -> Rect {
    guard directChildOfRoot,
          bounds.x.isFinite, bounds.y.isFinite, bounds.w.isFinite, bounds.h.isFinite,
          viewport.w.isFinite, viewport.h.isFinite,
          bounds.w >= 0, bounds.h >= 0, bounds.w <= viewport.w, bounds.h <= viewport.h else {
        return bounds
    }
    return Rect(x: (viewport.w - bounds.w) / 2,
                y: (viewport.h - bounds.h) / 2,
                w: bounds.w, h: bounds.h)
}
