import Foundation

/// Marker for List style selection metadata. Apple: https://developer.apple.com/documentation/swiftui/liststyle
/// The runtime records the selection (the layout depends on it) and the host draws it.
public protocol ListStyle: Sendable {}

/// `.automatic`: the platform default, which on macOS is the inset list.
public struct DefaultListStyle: ListStyle { public init() {} }
/// `.inset`: rows inset from the list's edges, rounded selection.
public struct InsetListStyle: ListStyle { public init() {} }
/// `.plain`: rows run edge to edge, flat selection.
public struct PlainListStyle: ListStyle { public init() {} }
/// `.sidebar`: not drawn by the host yet.
public struct SidebarListStyle: ListStyle { public init() {} }

public extension ListStyle where Self == DefaultListStyle { static var automatic: DefaultListStyle { DefaultListStyle() } }
public extension ListStyle where Self == InsetListStyle { static var inset: InsetListStyle { InsetListStyle() } }
public extension ListStyle where Self == PlainListStyle { static var plain: PlainListStyle { PlainListStyle() } }
public extension ListStyle where Self == SidebarListStyle { static var sidebar: SidebarListStyle { SidebarListStyle() } }

/// The look a List resolves to (the automatic style and an unset style are the inset list on macOS).
public enum ListLook: Equatable, Sendable {
    case inset, plain, sidebar

    /// `style` is `ResolvedNode.listStyle` (the style's type name), nil when no `.listStyle` applies.
    public init(style: String?) {
        switch style {
        case "PlainListStyle": self = .plain
        case "SidebarListStyle": self = .sidebar
        default: self = .inset
        }
    }
}

/// How a List is laid out on macOS, measured from SwiftUI on macOS 27 (`NSTableView` rows read from the hosting view's table, rendered at scale 2.5; see
/// factory/tools/switch-artwork/list-profile): a row is its content plus 8 pt above and below, at least 24 pt tall; the content starts 16 pt from the list's
/// leading edge (8 pt in the plain style) and is centred in the row; the inset style leaves 10 pt above the first row (the plain style none). A List takes the
/// whole proposed size (an unframed List in a window fills it; its ideal size is zero). The inset style also reserves a 16.8 pt trailing gutter for the
/// vertical scroller (`AXScrollBar` at the list's trailing edge, present although three rows fit): its rows end 16.8 pt before the list's trailing edge.
/// Measured on the macOS 27 inset List only (CI run 38854967920, controls-b, decision H21); the plain style's gutter is not measured, so it is none.
public enum ListMetrics {
    public static let rowMinHeight: CGFloat = 24
    public static let rowContentPadding: CGFloat = 8
    public static let insetScrollerGutter: CGFloat = 16.8

    /// The row's height for content of `contentHeight`.
    public static func rowHeight(forContent contentHeight: CGFloat) -> CGFloat { max(rowMinHeight, contentHeight + rowContentPadding) }

    public static func contentInset(_ look: ListLook) -> CGFloat { look == .plain ? 8 : 16 }
    public static func topInset(_ look: ListLook) -> CGFloat { look == .plain ? 0 : 10 }
    /// The width a List reserves at its trailing edge for the vertical scroller, outside every row (none in the plain style, unmeasured; see above).
    public static func trailingGutter(_ look: ListLook) -> CGFloat { look == .inset ? insetScrollerGutter : 0 }

    /// The rectangle of a row (`content` is the row content's frame in the List's coordinates, `listFrame` the List's), derived from the layout rules
    /// above: the row is `rowHeight` tall around its content, whose centre is the row's centre, and it spans the list's width less the trailing gutter.
    public static func rowFrame(content: LayoutRect, listFrame: LayoutRect, look: ListLook = .inset) -> LayoutRect {
        let height = rowHeight(forContent: content.height)
        let top = content.minY - (height - content.height) / 2
        return LayoutRect(x: listFrame.minX, y: top, width: listFrame.width - trailingGutter(look), height: height)
    }
}
