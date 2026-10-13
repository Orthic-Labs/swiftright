import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// How a List is painted on the host side: the list's own background and row separators, and for each row (a direct child of the List node) its selection
/// highlight. Row text paints itself (white inside an active selection). The numbers are measured from SwiftUI's default macOS List (an NSTableView in the inset
/// style, rendered at scale 2.5, light appearance; factory/tools/switch-artwork/list-profile): a row is its content plus 8 pt, at least 24 pt (`ListMetrics`);
/// separators are 1 pt lines in 230 (the pixel row above them at half coverage) along the bottom of every row except the last, from 16 pt inside the list's
/// leading edge to 16 pt inside its trailing edge (the plain style: from 8 pt to the edge), and hidden next to a selected row; the inset style's selection is a
/// rounded rectangle (corner outline measured, `ListHighlightArtwork`) 10 pt inside the list's edges, accent (0, 100, 225) while the list is the key view and grey 220 otherwise; the plain style's is a
/// flat full-width rectangle; the background is white. Nothing of Apple's artwork is embedded.
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
    }

    /// The full-width rectangle of every row (direct child) of a List, top to bottom, in window pixels, from the layout rules (`ListMetrics`): edges at
    /// whole device pixels (a half pixel rounds up, as AppKit lays the first row of a list at a half-pixel position).
    public static func rows(of list: ResolvedNode, bounds: Rect, scale: Float) -> [Row] {
        let look = look(of: list)
        var edge = (bounds.y + Float(ListMetrics.topInset(look)) * scale).rounded(.toNearestOrAwayFromZero)
        var out: [Row] = []
        var cursor = Float(ListMetrics.topInset(look))
        for child in list.children {
            cursor += Float(ListMetrics.rowHeight(forContent: CGFloat(child.frame.height)))
            let next = (bounds.y + cursor * scale).rounded(.toNearestOrAwayFromZero)
            out.append(Row(rect: Rect(x: bounds.x, y: edge, w: bounds.w, h: next - edge), isSelected: child.accessibility.isSelected, isEnabled: child.accessibility.isEnabled))
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
        for (i, row) in rows.enumerated() where i < rows.count - 1 && !row.isSelected && !rows[i + 1].isSelected {
            let x = bounds.x + inset, w = max(0, bounds.w - inset - right)
            let bottom = row.rect.y + row.rect.h
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

    public static func highlight(for row: Row, listBounds: Rect, look: ListLook, scale: Float, active: Bool) -> Highlight? {
        guard row.isSelected else { return nil }
        let rgb = selectionColor(active: active, isEnabled: row.isEnabled)
        if look == .plain { return .flat(row.rect, rgb << 8 | 0xff) }
        let inset = selectionInsetPoints * scale
        return .rounded(Rect(x: listBounds.x + inset, y: row.rect.y, w: listBounds.w - 2 * inset, h: row.rect.h), rgb: rgb)
    }
}
