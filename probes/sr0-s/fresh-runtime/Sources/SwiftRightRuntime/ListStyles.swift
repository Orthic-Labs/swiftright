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
/// whole proposed size (an unframed List in a window fills it; its ideal size is zero).
///
/// Vertical scrolling (H21, CI run 38868496881 and the fetched Mac accessibility trees). The inset style's scrollable document is its top inset, every
/// row and a 10 pt bottom inset (controls-b: AXOutline 92 pt = 10 + 3 x 24 + 10 in a 90 pt viewport). When that document is taller than the List, a legacy
/// (always-visible) vertical scroller is shown at the trailing edge and reserves 16.8 pt there (AXScrollBar at x 202 pt, width 19 pt, with the rows ending
/// at 203.2 pt). When the rows fit (five-rows: 140 pt in 160 pt) there is no scroller and the rows span the full width. The gutter is the legacy scroller's;
/// an overlay scroller takes no space. The factory pins the legacy style on its Mac reference (`factory/tools/mac-accessibility.sh`). SwiftRight draws no
/// scroll bar, so an overflowing List only clips its rows at the bottom (a known gap). The plain style has no measured bottom inset or gutter; it is none.
public enum ListMetrics {
    public static let rowMinHeight: CGFloat = 24
    public static let rowContentPadding: CGFloat = 8
    /// The legacy vertical scroller's reserved width at the inset List's trailing edge (measured, controls-b).
    public static let insetScrollerGutter: CGFloat = 16.8
    /// The inset List's bottom inset in its scrollable document (measured, controls-b: 10 + 72 + 10 = 92 pt).
    public static let insetBottomInset: CGFloat = 10

    /// The row's height for content of `contentHeight`.
    public static func rowHeight(forContent contentHeight: CGFloat) -> CGFloat { max(rowMinHeight, contentHeight + rowContentPadding) }

    public static func contentInset(_ look: ListLook) -> CGFloat { look == .plain ? 8 : 16 }
    public static func topInset(_ look: ListLook) -> CGFloat { look == .plain ? 0 : 10 }
    public static func bottomInset(_ look: ListLook) -> CGFloat { look == .inset ? insetBottomInset : 0 }

    /// The height of the List's scrollable document: its top inset, every row and its bottom inset.
    public static func documentHeight(_ look: ListLook, rowHeights: [CGFloat]) -> CGFloat {
        topInset(look) + rowHeights.reduce(0, +) + bottomInset(look)
    }

    /// Whether the rows overflow the List's viewport, so that a vertical scroller is shown (strictly taller: a document of exactly the viewport's height fits).
    public static func overflows(_ look: ListLook, rowHeights: [CGFloat], viewportHeight: CGFloat) -> Bool {
        documentHeight(look, rowHeights: rowHeights) > viewportHeight
    }

    /// The width a List reserves at its trailing edge for a legacy vertical scroller: the inset style's, and only when the rows overflow. Zero otherwise.
    public static func trailingGutter(_ look: ListLook, overflows: Bool) -> CGFloat { look == .inset && overflows ? insetScrollerGutter : 0 }

    /// The rectangle of a row (`content` is the row content's frame in the List's coordinates, `listFrame` the List's), derived from the layout rules
    /// above: the row is `rowHeight` tall around its content, whose centre is the row's centre, and it spans the list's width less `trailingGutter`.
    public static func rowFrame(content: LayoutRect, listFrame: LayoutRect, trailingGutter: CGFloat = 0) -> LayoutRect {
        let height = rowHeight(forContent: content.height)
        let top = content.minY - (height - content.height) / 2
        return LayoutRect(x: listFrame.minX, y: top, width: listFrame.width - trailingGutter, height: height)
    }
}

/// The scroll state of a List or a vertical ScrollView after layout (#31). Points. `offsetY` is clamped to 0...maxOffset.
/// `showsScroller` is true when the content overflows (and, for a ScrollView, its indicators are shown).
public struct ScrollState: Equatable, Sendable {
    public let offsetY: Double
    public let contentHeight: Double
    public let viewportHeight: Double
    public let showsScroller: Bool

    public init(offsetY: Double, contentHeight: Double, viewportHeight: Double, showsScroller: Bool) {
        self.offsetY = offsetY
        self.contentHeight = contentHeight
        self.viewportHeight = viewportHeight
        self.showsScroller = showsScroller
    }

    /// The largest offset: how far the content is taller than the viewport (0 when it fits).
    public var maxOffset: Double { max(0, contentHeight - viewportHeight) }
    /// The position of the offset in 0...1 (the scroller's accessibility value); 0 when nothing scrolls.
    public var value: Double { maxOffset > 0 ? offsetY / maxOffset : 0 }
}

/// Scroll wheel and scroll bar metrics (#31). Every value is provisional until the Mac measurement (M1-M3, #31) lands; each is marked TO MEASURE.
public enum ScrollerMetrics {
    /// Points a ScrollView's content moves for one wheel line: 10 (measured M2, run 39062962549: 1, 3, 10 lines -> 10, 30, 100 pt).
    /// A List moves by one row height per line instead (measured: 24 pt rows -> 24, 72, 240 pt), see `Graph.scrollWheel`.
    public static let pointsPerLine: CGFloat = 10
    /// Overlap kept between pages: a page is the viewport less this (measured M3, run 39068737526: Page Down moves 79.6 pt in an 89.6 pt clip,
    /// NSScrollView.verticalPageScroll = 10).
    public static let pageOverlap: CGFloat = 10
    /// Width of the drawn scroller at the trailing edge: 17 pt (measured M5, run 39068737526: NSScroller frame x 163, w 17 in a 180 pt scroll view).
    /// The 19 pt AXScrollBar of H21/M1 is its accessibility frame, 1 pt wider on each side.
    public static let width: CGFloat = 17
    /// Thumb inset from the drawn scroller's leading edge (M5: knobRect x 3.0; 4.0 from the AX frame's edge in M1).
    public static let thumbInsetLeading: CGFloat = 3
    /// Thumb inset from the drawn scroller's trailing edge (17 - 3 - 10.8).
    public static let thumbInsetTrailing: CGFloat = 3.2
    /// Track start below the viewport's top (M1: the bar spans the viewport plus 1 pt each side, the track starts 4.0 pt into the bar).
    public static let thumbInsetTop: CGFloat = 3.0
    /// Track end above the viewport's bottom (M1: the track ends 4.2 pt before the bar's end; track = viewport - 6.2).
    public static let thumbInsetBottom: CGFloat = 3.2
    /// Thumb width (M1: 10.8 pt).
    public static let thumbWidth: CGFloat = 10.8
    /// Shortest thumb (M1: a 620 pt document in an 89.6 pt viewport gives 20.0, where the proportion would give 12.1).
    public static let minThumbLength: CGFloat = 20

    /// The track's length: the viewport less the top and bottom insets.
    public static func trackLength(viewport: CGFloat) -> CGFloat { max(0, viewport - thumbInsetTop - thumbInsetBottom) }

    /// The thumb's length: track x viewport / content, at least `minThumbLength`.
    public static func thumbLength(viewport: CGFloat, content: CGFloat) -> CGFloat {
        guard content > 0 else { return minThumbLength }
        return max(minThumbLength, trackLength(viewport: viewport) * viewport / content)
    }
}
