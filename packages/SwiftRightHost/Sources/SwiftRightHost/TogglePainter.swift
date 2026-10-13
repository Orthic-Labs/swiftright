import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// How one Toggle node is painted: the control's artwork rasterised on the host side (registered as an image, like continuous shapes) and the
/// accessibility facts of the control. The label is a child node and paints itself.
public struct TogglePaintPlan {
    public var image: ContinuousRGBAImage
    /// Where the image goes (pixels, window coordinates).
    public var placement: Rect
    public var role: NodeRole
    public var toggled: ToggledState
    public var isEnabled: Bool
}

public enum TogglePainter {
    /// Resolves a Toggle node to its paint, from runtime geometry and state only. `bounds` is the node's pixel frame in window coordinates.
    public static func plan(_ node: ResolvedNode, bounds: Rect, scale: Float) throws -> TogglePaintPlan {
        guard let artwork = ToggleMetrics.artwork(forStyle: node.toggleStyle) else {
            throw HostPaintError.unsupportedToggleStyle(node.toggleStyle ?? "automatic")
        }
        guard node.opacity == 1, node.style.foreground == nil else { throw HostPaintError.unsupportedTogglePaintStyle }
        let width = (Float(artwork.controlSize.width) * scale).rounded(), height = (Float(artwork.controlSize.height) * scale).rounded()
        guard width > 0, height > 0 else { throw HostPaintError.unsupportedToggleStyle("empty control") }
        // The control sits on the side away from the label (the runtime lays out which side: trailing for a switch, leading for a checkbox, flipped
        // under right-to-left); alone it is the whole frame, centred vertically.
        let x: Float
        var offsetY: Float = 0
        if let label = node.children.first {
            offsetY = Float(artwork.labelledControlOffsetY) * scale
            let labelMid = Float(label.pixelFrame.x) + Float(label.pixelFrame.width) / 2
            let nodeMid = Float(node.pixelFrame.x) + Float(node.pixelFrame.width) / 2
            x = labelMid < nodeMid ? bounds.x + bounds.w - width : bounds.x
        } else {
            x = bounds.x
        }
        let y = bounds.y + ((bounds.h - height) / 2 + offsetY).rounded()
        let isOn = node.accessibility.value == "1"
        let isEnabled = node.accessibility.isEnabled
        let image: ContinuousRGBAImage
        let role: NodeRole
        switch artwork {
        case .switchControl:
            image = SwitchArtwork.render(widthPX: Int(width), heightPX: Int(height), isOn: isOn, isEnabled: isEnabled)
            role = .switchControl
        case .checkbox:
            image = CheckboxArtwork.render(widthPX: Int(width), heightPX: Int(height), isOn: isOn, isEnabled: isEnabled)
            role = .checkbox
        }
        return TogglePaintPlan(
            image: image,
            placement: Rect(x: x + imageGuardBand, y: y + imageGuardBand, w: width - 2 * imageGuardBand, h: height - 2 * imageGuardBand),
            role: role, toggled: isOn ? .on : .off, isEnabled: isEnabled)
    }
}
