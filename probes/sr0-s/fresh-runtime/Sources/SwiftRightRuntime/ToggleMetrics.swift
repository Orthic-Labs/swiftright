import Foundation

/// How a Toggle is drawn on macOS, which decides its intrinsic size. The artwork itself is host-owned (SwiftRightHost); the runtime only
/// needs the control's layout metrics so that a Toggle takes the space SwiftUI gives it.
public enum ToggleArtwork: Equatable, Sendable {
    /// `.toggleStyle(.switch)`: a 54 x 24 pt switch.
    case switchControl

    /// Size of the control without its label, in points. Measured from SwiftUI on macOS (AppKit-hosted switch, `fittingSize`).
    public var controlSize: LayoutSize {
        switch self {
        case .switchControl: return LayoutSize(width: 54, height: 24)
        }
    }

    /// Distance between the label and the control, in points.
    public var labelSpacing: CGFloat {
        switch self {
        case .switchControl: return 8
        }
    }
}

public enum ToggleMetrics {
    /// The artwork a `.toggleStyle` selection resolves to. `style` is `ResolvedNode.toggleStyle`, nil when no `.toggleStyle` applies.
    public static func artwork(forStyle style: String?) -> ToggleArtwork? {
        switch style {
        case "SwitchToggleStyle": return .switchControl
        default: return nil
        }
    }
}
