import Foundation
import SwiftRightRuntime

/// Translation applied to every resolved node in one intrinsic root subtree.
/// Background node is created separately by host and remains unchanged.
struct FactoryRootSubtreeTranslation {
    let dx: Float
    let dy: Float

    func applying(to bounds: Rect) -> Rect {
        guard bounds.x.isFinite, bounds.y.isFinite,
              bounds.w.isFinite, bounds.h.isFinite else { return bounds }
        return Rect(x: bounds.x + dx, y: bounds.y + dy, w: bounds.w, h: bounds.h)
    }
}

/// Center intrinsic runtime root in host viewport. Root size, rather than a
/// leaf kind or parent identity, determines translation for complete subtree.
func factoryCenteredRootSubtree(_ rootBounds: Rect, viewport: Rect) -> FactoryRootSubtreeTranslation? {
    guard rootBounds.x.isFinite, rootBounds.y.isFinite,
          rootBounds.w.isFinite, rootBounds.h.isFinite,
          viewport.x.isFinite, viewport.y.isFinite,
          viewport.w.isFinite, viewport.h.isFinite,
          rootBounds.w >= 0, rootBounds.h >= 0,
          viewport.w >= 0, viewport.h >= 0,
          rootBounds.w <= viewport.w, rootBounds.h <= viewport.h else {
        return nil
    }
    return FactoryRootSubtreeTranslation(
        dx: viewport.x + (viewport.w - rootBounds.w) / 2 - rootBounds.x,
        dy: viewport.y + (viewport.h - rootBounds.h) / 2 - rootBounds.y
    )
}
