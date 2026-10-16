import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// How a List is painted on the host side: the list's own background and row separators, and for each row (a direct child of the List node) its selection
/// highlight. Row text paints itself (white inside an active selection). The numbers are measured from SwiftUI's default macOS List (an NSTableView in the inset
/// style, rendered at scale 2.5, light appearance; factory/tools/switch-artwork/list-profile): a row is its content plus 8 pt, at least 24 pt (`ListMetrics`);
/// separators are 1 pt lines in 230 (the pixel row above them at half coverage) along the bottom of every row except the last, from 16 pt inside the row's
/// leading edge to 16 pt inside its trailing edge (the plain style: from 8 pt to the edge), and hidden next to a selected row; the inset style's selection is a
/// rounded rectangle (corner outline measured, `ListHighlightArtwork`) 10 pt inside the row's edges, accent (0, 100, 225) while the list is the key view and grey 220 otherwise; the plain style's is a
/// flat full-width rectangle; the background is white. The inset style's rows end 16.8 pt before the list's trailing edge (the vertical scroller's reserved gutter, H21),
/// so its row, selection and separator measures are taken from the row, not the list. Nothing of Apple's artwork is embedded.
public enum ListPainter {
    public static let background: UInt32 = 0xffffffff
    public static let separatorRGB: UInt32 = 0xe6e6e6
    public static let selectionActive: UInt32 = 0x0064e1
    public static let selectionInactive: UInt32 = 0xdcdcdc
    public static let selectionInsetPoints: Float = 10
        public static let separatorInsetPoints: Float = 16
    public static let selectedTextColor: UInt32 = 0xffffffff

    public static func look(of node: ResolvedNode) -> ListLook { ListLook(style: node.listStyle) }

    /// One row's rectangle in window pixels, and what it needs to paint.
    public struct Row {
        public var rect: Rect
        public var isSelected: Bool
        public var isEnabled: Bool
        /// `.listRowSeparator(.hidden)` on the row's content: its bottom separator is not drawn.
        public var separatorHidden = false
        /// `.listRowBackground(_:)`: the row's own background (nil: the list's). `backgroundUnsupported`: some other view, which fails visibly.
        public var background: ResolvedColor? = nil
        public var backgroundUnsupported = false
    }

    /// The row modifiers of a row: the `listRowSeparator` / `listRowBackground` modifier nodes on the single-child chain below the row's top node (a `.tag` or another
    /// modifier may wrap them), the outermost winning.
    static func rowStyle(of child: ResolvedNode) -> (separatorHidden: Bool?, setsBackground: Bool, background: ResolvedColor?, unsupported: Bool) {
        var separatorHidden: Bool?, setsBackground = false, background: ResolvedColor?, unsupported = false
        var node: ResolvedNode? = child
        while let n = node {
            if let s = n.rowStyle {
                if separatorHidden == nil { separatorHidden = s.separatorHidden }
                if !setsBackground, s.setsBackground { setsBackground = true; background = s.background; unsupported = s.backgroundUnsupported }
            }
            node = n.children.count == 1 ? n.children[0] : nil
        }
        return (separatorHidden, setsBackground, background, unsupported)
    }

    /// The rectangle of every row (direct child) of a List, top to bottom, in window pixels, from the layout rules (`ListMetrics`): the list's width less the
    /// trailing scroller gutter (16.8 pt in the inset style, 42 px at scale 2.5; none in the plain style), and edges at whole device pixels (a half pixel rounds
    /// up, as AppKit lays the first row of a list at a half-pixel position).
    public static func rows(of list: ResolvedNode, bounds: Rect, scale: Float) -> [Row] {
        let look = look(of: list)
        let gutter = (Float(ListMetrics.trailingGutter(look)) * scale).rounded(.toNearestOrAwayFromZero)
        let rowWidth = max(0, bounds.w - gutter)
        var edge = (bounds.y + Float(ListMetrics.topInset(look)) * scale).rounded(.toNearestOrAwayFromZero)
        var out: [Row] = []
        var cursor = Float(ListMetrics.topInset(look))
        for child in list.children {
            cursor += Float(ListMetrics.rowHeight(forContent: CGFloat(child.frame.height)))
            let next = (bounds.y + cursor * scale).rounded(.toNearestOrAwayFromZero)
            let style = rowStyle(of: child)
            out.append(Row(rect: Rect(x: bounds.x, y: edge, w: rowWidth, h: next - edge), isSelected: child.accessibility.isSelected, isEnabled: child.accessibility.isEnabled,
                           separatorHidden: style.separatorHidden ?? false, background: style.background, backgroundUnsupported: style.unsupported))
            edge = next
        }
        return out
    }

    /// Whether the list's selection paints in the key (accent) colour: the host says the list holds the keyboard, and a disabled list never does.
    public static func selectionColor(active: Bool, isEnabled: Bool) -> UInt32 { active && isEnabled ? selectionActive : selectionInactive }

    /// The list's own primitives: its background and the separators, clipped to its bounds (rows below the bottom edge are laid out and clipped).
    public static func primitives(for list: ResolvedNode, bounds: Rect, scale: Float) throws -> [Primitive] {
        let look = look(of: list)
        guard look != .sidebar else { throw HostPaintError.unsupportedListStyle("sidebar") }
        var out: [Primitive] = [.clipPush(bounds), .rect(bounds, color: background << 8 | 0xff)]
        let rows = rows(of: list, bounds: bounds, scale: scale)
        let inset = (look == .plain ? 8 : separatorInsetPoints) * scale
        let right = look == .plain ? 0 : separatorInsetPoints * scale
        let thickness = scale                       // 1 pt
        let whole = thickness.rounded(.down), partial = thickness - whole
        let rgb = separatorRGB
        // A row background (`.listRowBackground`) fills the whole row rectangle (the list's inset above the first row stays the list's own).
        for row in rows {
            if row.backgroundUnsupported { throw HostPaintError.unsupportedNode("listRowBackground (only a Color or a Rectangle filled with a Color is drawn)") }
            if let fill = row.background { out.append(.rect(row.rect, color: try HostPaint.rgba(fill, opacity: 1))) }
        }
        for (i, row) in rows.enumerated() where i < rows.count - 1 && !row.isSelected && !rows[i + 1].isSelected && !row.separatorHidden {
            // the separator spans its row (inset from the row's edges, not the list's)
            let x = row.rect.x + inset, w = max(0, row.rect.w - inset - right)
            let bottom = row.rect.y + row.rect.h
            if row.background != nil {
                // over a coloured row the separator is the translucent black it is (alpha 25/255, as the Divider), not the flat grey that equals it over white
                out.append(.rect(Rect(x: x, y: bottom - whole, w: w, h: whole), color: 0x00000019))
                if partial > 0 { out.append(.rect(Rect(x: x, y: bottom - whole - 1, w: w, h: 1), color: UInt32((25 * partial).rounded()))) }
                continue
            }
            out.append(.rect(Rect(x: x, y: bottom - whole, w: w, h: whole), color: rgb << 8 | 0xff))
            if partial > 0 {
                let c = UInt32((255 - (255 - Float(rgb & 255)) * partial).rounded())
                out.append(.rect(Rect(x: x, y: bottom - whole - 1, w: w, h: 1), color: c << 24 | c << 16 | c << 8 | 0xff))
            }
        }
        out.append(.clipPop)
        return out
    }

    /// The selection highlight of a selected row: nil for an unselected row. The inset style's is a rasterised rounded rectangle (`ListHighlightArtwork`: the
    /// corner outline measured from SwiftUI), the plain style's a flat rect.
    public enum Highlight {
        case flat(Rect, UInt32)
        case rounded(Rect, rgb: UInt32)
    }

    public static func highlight(for row: Row, look: ListLook, scale: Float, active: Bool) -> Highlight? {
        guard row.isSelected, row.background == nil else { return nil }   // a row background replaces the selection highlight (measured: the highlight is not drawn over it)
        let rgb = selectionColor(active: active, isEnabled: row.isEnabled)
        if look == .plain { return .flat(row.rect, rgb << 8 | 0xff) }
        let inset = selectionInsetPoints * scale
        return .rounded(Rect(x: row.rect.x + inset, y: row.rect.y, w: max(0, row.rect.w - 2 * inset), h: row.rect.h), rgb: rgb)
    }
}
