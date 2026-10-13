import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// How one Button node is painted: the button artwork rasterised on the host side (registered as an image, like the Toggle control) behind its
/// label, which is a child node and paints itself in the button's label colour.
public struct ButtonPaintPlan {
    public var image: ContinuousRGBAImage
    /// Where the image goes (pixels, window coordinates).
    public var placement: Rect
    public var isEnabled: Bool
}

public enum ButtonPainter {
    /// Resolves a Button node to its paint, from runtime geometry and state only. `bounds` is the node's pixel frame in window coordinates.
    public static func plan(_ node: ResolvedNode, bounds: Rect, scale: Float) throws -> ButtonPaintPlan {
        guard node.opacity == 1, node.style.foreground == nil else { throw HostPaintError.unsupportedButtonPaintStyle }
        let width = bounds.w.rounded(), height = bounds.h.rounded()
        guard width > 0, height > 0 else { throw HostPaintError.unsupportedButtonPaintStyle }
        let isEnabled = node.accessibility.isEnabled
        let image = ButtonArtwork.render(widthPX: Int(width), heightPX: Int(height), scale: scale, isEnabled: isEnabled)
        return ButtonPaintPlan(image: image,
                               placement: Rect(x: bounds.x + imageGuardBand, y: bounds.y + imageGuardBand, w: width - 2 * imageGuardBand, h: height - 2 * imageGuardBand),
                               isEnabled: isEnabled)
    }
}
