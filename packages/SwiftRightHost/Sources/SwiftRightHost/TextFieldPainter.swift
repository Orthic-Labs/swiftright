import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Colours of a TextField's text (light appearance, read from the macOS render: the darkest glyph pixel of typed text and of the placeholder).
public enum TextFieldColors {
    public static let text: UInt32 = 0x212121ff
    public static let placeholder: UInt32 = 0x767676ff
    public static let plainPlaceholder: UInt32 = 0x404040ff
    /// Selection highlight and caret: reported state, not gated (the pixel gate runs on an unfocused field).
    public static let selection: UInt32 = 0x99c9efff
    public static let caret: UInt32 = 0x111111ff
}

/// Caret and range geometry of a shaped run: x positions in pixels (relative to the run's left) at each UTF-16 offset.
public enum TextFieldGeometry {
    /// `xs[i]` is the x of the boundary before UTF-16 unit `i`; `xs[count]` is the end. Units inside a surrogate pair share their cell's start.
    public static func boundaries(text: String, cells: [CharCell], runWidth: Float) -> [Float] {
        let units = text.utf16.count
        guard units > 0 else { return [0] }
        guard !cells.isEmpty else { return (0...units).map { Float($0) / Float(units) * runWidth } }
        var xs = [Float](repeating: runWidth, count: units + 1)
        // utf8 offset -> utf16 offset
        var utf16At: [Int: Int] = [:]
        var u8 = 0, u16 = 0
        for scalar in text.unicodeScalars {
            utf16At[u8] = u16
            u8 += String(scalar).utf8.count
            u16 += scalar.value > 0xFFFF ? 2 : 1
        }
        utf16At[u8] = u16
        var filled = Set<Int>()
        for cell in cells {
            guard let start = utf16At[Int(cell.utf8Offset)], let end = utf16At[Int(cell.utf8Offset + cell.utf8Len)] else { continue }
            xs[start] = cell.x0; filled.insert(start)
            xs[end] = cell.x1; filled.insert(end)
            if end - start > 1 { for k in (start + 1)..<end { xs[k] = cell.x0 } }
        }
        return xs
    }
}

/// Where a painted TextField put its text, in window pixels: the origin of the shaped text and the x of every UTF-16 boundary. A pointer
/// host places the caret with it and an IME host anchors the candidate window.
public struct TextFieldLayout: Equatable {
    public var bounds: Rect
    public var textOriginX: Float
    public var boundaries: [Float]
    public var lineHeight: Float
    public var textTop: Float

    /// The UTF-16 offset whose boundary is nearest to window x `x`.
    public func offset(atX x: Float) -> Int {
        guard !boundaries.isEmpty else { return 0 }
        let local = x - textOriginX
        var best = 0
        for (i, b) in boundaries.enumerated() where abs(b - local) < abs(boundaries[best] - local) { best = i }
        return best
    }

    /// The window x of a UTF-16 offset (clamped).
    public func x(ofOffset offset: Int) -> Float {
        guard !boundaries.isEmpty else { return textOriginX }
        return textOriginX + boundaries[min(max(offset, 0), boundaries.count - 1)]
    }
}

extension ResolvedNodePainter {
    /// TextField: the bezel (a registered image) for the bezeled styles, the typed text or the placeholder as a shaped run clipped to the field,
    /// and for the focused field the selection highlight, caret and marked-text underline. Semantics: a text-field node with the committed value.
    func emitTextField(_ node: ResolvedNode, id: UInt64, bounds: Rect) throws -> NodeEmission {
        guard let text else { throw HostPaintError.unsupportedNode("TextField (no text measurer)") }
        let artwork = TextFieldMetrics.artwork(forStyle: node.fieldStyle)
        let isEnabled = node.accessibility.isEnabled
        var primitives: [Primitive] = []
        if artwork == .bezel {
            let bezel = TextFieldArtwork.render(widthPX: Int(bounds.w), heightPX: Int(bounds.h), scale: Double(scale), scheme: node.style.colorScheme)
            let handle = try images.registerImage(width: UInt32(bezel.image.width), height: UInt32(bezel.image.height), rgba: bezel.image.rgba, stride: 0)
            if let stale = pendingShapeImages[id] { _ = images.release(stale) }
            pendingShapeImages[id] = handle
            let pad = Float(bezel.pad)
            primitives.append(.image(handle, Rect(x: bounds.x - pad + imageGuardBand, y: bounds.y - pad + imageGuardBand,
                                                  w: Float(bezel.image.width) - 2 * imageGuardBand, h: Float(bezel.image.height) - 2 * imageGuardBand)))
        }
        let shown = node.text ?? ""
        let isPlaceholder = shown.isEmpty
        let content = isPlaceholder ? (node.placeholder ?? "") : shown
        let isFocused = focusedFieldID == node.id
        let inset = Float(TextFieldMetrics.textInset(artwork)) * scale
        let clip = Rect(x: bounds.x + inset, y: bounds.y, w: max(0, bounds.w - 2 * inset), h: bounds.h)
        if !content.isEmpty {
            let color: UInt32
            if isPlaceholder { color = artwork == .plain ? TextFieldColors.plainPlaceholder : TextFieldColors.placeholder }
            else { color = try node.style.foreground.map { try HostPaint.rgba($0, opacity: 1, scheme: node.style.colorScheme) } ?? TextFieldColors.text }
            guard let natural = try text.naturalRun(text: content, font: node.style.font, color: color) else {
                throw HostPaintError.measuredRunGeometryMismatch(content)
            }
            let originY = bounds.y + ((bounds.h - natural.height) / 2).rounded()
            var originX = bounds.x + inset
            let xs = isPlaceholder ? [] : TextFieldGeometry.boundaries(text: content, cells: text.cells(of: natural.run), runWidth: natural.width)
            // A focused field scrolls to keep its caret inside (AppKit's field editor does the same).
            if isFocused, !isPlaceholder, let selection = node.selection {
                let caret = xs[min(max(selection.location + selection.length, 0), xs.count - 1)]
                let visible = max(0, clip.w)
                if caret > visible { originX -= caret - visible }
            }
            pendingFieldLayouts[node.id] = TextFieldLayout(bounds: bounds, textOriginX: originX, boundaries: isPlaceholder ? [0] : xs,
                                                           lineHeight: natural.height, textTop: originY)
            primitives.append(.clipPush(clip))
            if isFocused, !isPlaceholder, let selection = node.selection, selection.length > 0, selection.location + selection.length < xs.count {
                let a = xs[selection.location], b = xs[selection.location + selection.length]
                primitives.append(.rect(Rect(x: originX + a, y: originY, w: max(1, b - a), h: natural.height), color: TextFieldColors.selection))
            }
            primitives.append(.text(natural.run, x: originX, y: originY))
            if isFocused, !isPlaceholder {
                if let marked = node.marked, marked.length > 0, marked.location + marked.length < xs.count {
                    let a = xs[marked.location], b = xs[marked.location + marked.length]
                    primitives.append(.underline(Rect(x: originX + a, y: originY + natural.height - max(1, scale / 2), w: max(1, b - a), h: max(1, scale / 2)), color: TextFieldColors.caret))
                }
                if let selection = node.selection, selection.length == 0, selection.location < xs.count {
                    primitives.append(.rect(Rect(x: originX + xs[selection.location], y: originY, w: max(1, scale / 2), h: natural.height), color: TextFieldColors.caret))
                }
            }
            if isFocused, isPlaceholder {
                primitives.append(.rect(Rect(x: bounds.x + inset, y: originY, w: max(1, scale / 2), h: natural.height), color: TextFieldColors.caret))
            }
            primitives.append(.clipPop)
        } else {
            let height = bounds.h - 2 * (artwork == .bezel ? Float(TextFieldMetrics.bezelTextInset) * scale : 0)
            let top = bounds.y + (bounds.h - height) / 2
            pendingFieldLayouts[node.id] = TextFieldLayout(bounds: bounds, textOriginX: bounds.x + inset, boundaries: [0], lineHeight: height, textTop: top)
            if isFocused {
                primitives.append(.rect(Rect(x: bounds.x + inset, y: top, w: max(1, scale / 2), h: height), color: TextFieldColors.caret))
            }
        }
        let semantic = SemanticNode(role: .textField, label: node.placeholder ?? node.accessibility.label ?? ""  /* macOS exposes the placeholder (prompt, else title) as the field name */, value: shown,
                                    actions: isEnabled ? [.focus, .setValue, .setSelection] : [], identifier: node.id, disabled: !isEnabled)
        return NodeEmission(primitives: primitives, semantic: semantic, flags: isEnabled ? [.hitTarget, .focusable, .editable] : [], structural: false)
    }
}
