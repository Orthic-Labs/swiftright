import Foundation

/// How a Toggle is drawn on macOS, which decides its intrinsic size. The artwork itself is host-owned (SwiftRightHost); the runtime only
/// needs the control's layout metrics so that a Toggle takes the space SwiftUI gives it.
public enum ToggleArtwork: Equatable, Sendable {
    /// `.toggleStyle(.switch)`: a 54 x 24 pt switch after its label.
    case switchControl
    /// The default style (`.automatic`, `.checkbox`) on macOS: a 16 x 16 pt checkbox before its label.
    case checkbox

    /// Size of the control without its label, in points. Measured from SwiftUI on macOS (AppKit-hosted control, `fittingSize`).
    public var controlSize: LayoutSize {
        switch self {
        case .switchControl: return LayoutSize(width: 54, height: 24)
        case .checkbox: return LayoutSize(width: 16, height: 16)
        }
    }

    /// Distance between the label and the control, in points.
    public var labelSpacing: CGFloat {
        switch self {
        case .switchControl: return 8
        case .checkbox: return 4.8
        }
    }

    /// How far below the vertical centre of its row the control is drawn when the Toggle has a label, in points. AppKit sets a labelled checkbox
    /// 0.8 pt low (its box is not centred on the text line); an unlabelled control, and a switch, are centred.
    public var labelledControlOffsetY: CGFloat {
        switch self {
        case .switchControl: return 0
        case .checkbox: return 0.8
        }
    }

    /// Whether the label comes first in a left-to-right layout (the switch trails its label, the checkbox leads it).
    public var labelLeads: Bool {
        switch self {
        case .switchControl: return true
        case .checkbox: return false
        }
    }
}

public enum ToggleMetrics {
    /// The artwork a `.toggleStyle` selection resolves to. `style` is `ResolvedNode.toggleStyle`, nil when no `.toggleStyle` applies, which is
    /// the platform default: a checkbox on macOS. Styles without drawn artwork resolve to nil.
    public static func artwork(forStyle style: String?) -> ToggleArtwork? {
        switch style {
        case "SwitchToggleStyle": return .switchControl
        case nil, "DefaultToggleStyle", "CheckboxToggleStyle": return .checkbox
        default: return nil
        }
    }
}
