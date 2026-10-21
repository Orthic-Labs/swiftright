import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// How one Button node is painted: the button artwork rasterised on the host side (registered as an image, like the Toggle control) behind its
/// label, which is a child node and paints itself in the button's label colour. `.borderless` and `.plain` have no body: `image` is nil and only
/// the label paints.
public struct ButtonPaintPlan {
    public var image: ContinuousRGBAImage?
    /// Where the image goes (pixels, window coordinates).
    public var placement: Rect
    public var isEnabled: Bool
    public var look: ButtonLook
    /// The colour the label's Text takes (0xRRGGBBAA), nil when it keeps its own default (`.plain`, enabled). A label's own foreground wins.
    public var labelColor: UInt32?
}

public enum ButtonPainter {
    public static func look(of node: ResolvedNode) -> ButtonLook { ButtonLook(style: node.buttonStyle, isDefaultAction: node.isDefaultButton && node.accessibility.isEnabled) }

    /// The colour a Button gives its label, 0xRRGGBBAA, or nil when the label keeps its own. A foreground style on a `.borderless` or `.plain`
    /// button colours the label (measured: `.plain` dims to half opacity when disabled, `.borderless` does not); on a `.prominent` button it is
    /// ignored (measured: the fill stays accent and the label white); on a `.bordered` button it tints the fill too, which is not modelled.
    public static func labelColor(of node: ResolvedNode) throws -> UInt32? {
        let look = look(of: node)
        let enabled = node.accessibility.isEnabled
        if let foreground = node.style.foreground, look == .borderless || look == .plain {
            let colour = try HostPaint.rgba(foreground, opacity: node.opacity, scheme: node.style.colorScheme)
            guard look == .plain, !enabled else { return colour }
            return (colour & 0xffffff00) | UInt32((Double(colour & 255) / 2).rounded())
        }
        if look == .plain, !enabled {
            // The label's default colour at half opacity (measured 0x939393 over white for the 0x272727 label).
            let colour = try HostPaint.rgba(.semantic("label"), opacity: node.opacity, scheme: node.style.colorScheme)
            return (colour & 0xffffff00) | UInt32((Double(colour & 255) / 2).rounded())
        }
        return ButtonArtwork.labelColor(look: look, isEnabled: enabled, dark: node.style.colorScheme == .dark).map { $0 << 8 | 0xff }
    }

    /// Resolves a Button node to its paint, from runtime geometry and state only. `bounds` is the node's pixel frame in window coordinates.
    public static func plan(_ node: ResolvedNode, bounds: Rect, scale: Float) throws -> ButtonPaintPlan {
        let look = look(of: node)
        // `.plain` and `.borderless` have no artwork: opacity reaches their label's colour (`labelColor`). A bodied look would need group opacity over its artwork, not modelled.
        guard node.opacity == 1 || !look.hasBody else { throw HostPaintError.unsupportedButtonPaintStyle }
        if node.style.foreground != nil, look == .bordered { throw HostPaintError.unsupportedButtonPaintStyle }
        let isEnabled = node.accessibility.isEnabled
        let width = bounds.w.rounded(), height = bounds.h.rounded()
        guard look.hasBody else {
            return ButtonPaintPlan(image: nil, placement: bounds, isEnabled: isEnabled, look: look, labelColor: try labelColor(of: node))
        }
        // An empty frame (a Button laid out at zero size) has nothing to draw; SwiftUI draws nothing for it.
        guard width > 0, height > 0 else { return ButtonPaintPlan(image: nil, placement: bounds, isEnabled: isEnabled, look: look, labelColor: try labelColor(of: node)) }
        let image = ButtonArtwork.render(widthPX: Int(width), heightPX: Int(height), scale: scale, isEnabled: isEnabled, prominent: look == .prominent, dark: node.style.colorScheme == .dark,
                                         tint: AccentTint.rgb(of: node))
        return ButtonPaintPlan(image: image,
                               placement: Rect(x: bounds.x + imageGuardBand, y: bounds.y + imageGuardBand, w: width - 2 * imageGuardBand, h: height - 2 * imageGuardBand),
                               isEnabled: isEnabled, look: look, labelColor: try labelColor(of: node))
    }
}
