import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Colours of a TextField's text (light appearance, read from the macOS render: the darkest glyph pixel of typed text and of the placeholder).
public enum TextFieldColors {
    public static let text: UInt32 = 0x212121ff
    public static let placeholder: UInt32 = 0x767676ff
    public static let plainPlaceholder: UInt32 = 0x404040ff
    /// Selection highlight: NSColor.selectedTextBackgroundColor in the aqua appearance (accent (0,122,255) at 30% over white = (179,215,255)), the
    /// emphasized colour the Mac captures show (the field editor is first responder in a key-appearance window). Read from AppKit by
    /// `factory/tools/appkit-probe`. Dark appearance (63,99,139) and the unemphasized grey (220) are not painted.
    public static let selection: UInt32 = 0xb3d7ffff
    /// Caret: reported state.
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

    /// The line and x (pixels from the line's start) of the boundary before each UTF-16 unit of a wrapped run (a vertical-axis field), and of its end: `positions[i]`
    /// for `i` in `0...count`. A boundary shared by the end of one line and the start of the next belongs to the next line (the caret sits at the start of the wrapped line);
    /// the end of the text is where its last character ends.
    public static func positions(text: String, cells: [CharCell], runWidth: Float) -> [(line: Int, x: Float)] {
        let units = text.utf16.count
        guard units > 0 else { return [(0, 0)] }
        guard !cells.isEmpty else { return (0...units).map { (0, Float($0) / Float(units) * runWidth) } }
        var out = [(line: Int, x: Float)](repeating: (0, 0), count: units + 1)
        var utf16At: [Int: Int] = [:]
        var u8 = 0, u16 = 0
        for scalar in text.unicodeScalars {
            utf16At[u8] = u16
            u8 += String(scalar).utf8.count
            u16 += scalar.value > 0xFFFF ? 2 : 1
        }
        utf16At[u8] = u16
        for cell in cells {
            guard let start = utf16At[Int(cell.utf8Offset)], let end = utf16At[Int(cell.utf8Offset + cell.utf8Len)] else { continue }
            let line = Int(cell.line)
            out[end] = (line, cell.x1)
            out[start] = (line, cell.x0)
            if end - start > 1 { for k in (start + 1)..<end { out[k] = (line, cell.x0) } }
        }
        return out
    }

    /// The width of each line of a wrapped run (the right edge of its last cell), by line index.
    public static func lineWidths(cells: [CharCell]) -> [Int: Float] {
        var out: [Int: Float] = [:]
        for cell in cells { out[Int(cell.line)] = max(out[Int(cell.line)] ?? 0, cell.x1) }
        return out
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
        let inset = Float(TextFieldMetrics.textOrigin(artwork)) * scale          // where the text starts (bezel: 6 pt)
        let clipInset = Float(TextFieldMetrics.textInset(artwork)) * scale        // the cell's content rect clips it (bezel: 4 pt each side; Mac: ink reaches 4 pt from the right edge)
        let clip = Rect(x: bounds.x + clipInset, y: bounds.y, w: max(0, bounds.w - 2 * clipInset), h: bounds.h)
        if !content.isEmpty, let field = node.verticalField {
            // F9: a vertical-axis field paints its text wrapped, the lines the field shows, scrolled to keep the caret in view
            let color: UInt32
            if isPlaceholder { color = artwork == .plain ? TextFieldColors.plainPlaceholder : TextFieldColors.placeholder }
            else { color = try node.style.foreground.map { try HostPaint.rgba($0, opacity: 1, scheme: node.style.colorScheme) } ?? TextFieldColors.text }
            primitives += try wrappedFieldPrimitives(node, field: field, content: content, isPlaceholder: isPlaceholder, color: color, artwork: artwork, bounds: bounds,
                                                     inset: inset, clipInset: clipInset, isFocused: isFocused)
        } else if !content.isEmpty {
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
                let visible = max(0, clip.x + clip.w - (bounds.x + inset))
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

    /// The primitives of a vertical-axis field's text (F9): the shaped run wrapped at `field.wrapWidth`, placed at the cell's top (the bezel's 4 pt inset) and shifted up when the
    /// text is taller than the lines the field shows, clipped to the content rect; for the focused field the selection (one rect per line it touches), the marked-text underline
    /// and the caret. Pointer hit-testing of the caret uses `TextFieldLayout`, which stays the single-line one: placing the caret by a click in a wrapped field is not delivered.
    func wrappedFieldPrimitives(_ node: ResolvedNode, field: ResolvedVerticalField, content: String, isPlaceholder: Bool, color: UInt32, artwork: TextFieldMetrics.Artwork,
                                bounds: Rect, inset: Float, clipInset: Float, isFocused: Bool) throws -> [Primitive] {
        guard let text else { throw HostPaintError.unsupportedNode("TextField (no text measurer)") }
        let topPad = artwork == .bezel ? Float(TextFieldMetrics.bezelTextInset) * scale : 0
        let visibleHeight = max(0, bounds.h - 2 * topPad)
        let lineHeight = Float(field.lineHeight) * scale
        let originX = bounds.x + inset
        let runBounds = Rect(x: originX, y: bounds.y + topPad, w: Float(field.textWidth) * scale, h: Float(field.textHeight) * scale)
        let run = try text.run(text: content, font: node.style.font, bounds: runBounds, color: color)
        let cells = isPlaceholder ? [] : text.cells(of: run)
        let positions = isPlaceholder ? [] : TextFieldGeometry.positions(text: content, cells: cells, runWidth: runBounds.w)
        let widths = TextFieldGeometry.lineWidths(cells: cells)
        // The field scrolls by whole lines to keep the caret's line inside the lines it shows (a field at its line limit).
        var scroll: Float = 0
        let overflow = max(0, runBounds.h - visibleHeight)
        if overflow > 0.5, isFocused, !isPlaceholder, let selection = node.selection {
            let offset = min(max(selection.location + selection.length, 0), positions.count - 1)
            let caretBottom = Float(positions[offset].line + 1) * lineHeight
            scroll = min(max(0, caretBottom - visibleHeight), overflow)
        }
        let top = bounds.y + topPad - scroll
        let clip = Rect(x: bounds.x + clipInset, y: bounds.y + topPad, w: max(0, bounds.w - 2 * clipInset), h: visibleHeight)
        /// One rect per line the range [a, b) touches, `height` tall from each line's `yOffset`.
        func lineRects(_ a: Int, _ b: Int, height: Float, yOffset: Float) -> [Rect] {
            guard a < b, a < positions.count, b < positions.count else { return [] }
            var out: [Rect] = []
            for line in positions[a].line...positions[b].line {
                let from = line == positions[a].line ? positions[a].x : 0
                let to = line == positions[b].line ? positions[b].x : (widths[line] ?? positions[b].x)
                out.append(Rect(x: originX + from, y: top + Float(line) * lineHeight + yOffset, w: max(1, to - from), h: height))
            }
            return out
        }
        var primitives: [Primitive] = [.clipPush(clip)]
        if isFocused, !isPlaceholder, let selection = node.selection, selection.length > 0 {
            for r in lineRects(selection.location, selection.location + selection.length, height: lineHeight, yOffset: 0) { primitives.append(.rect(r, color: TextFieldColors.selection)) }
        }
        primitives.append(.text(run, x: originX, y: top))
        if isFocused, !isPlaceholder {
            if let marked = node.marked, marked.length > 0 {
                let thin = max(1, scale / 2)
                for r in lineRects(marked.location, marked.location + marked.length, height: thin, yOffset: lineHeight - thin) { primitives.append(.underline(r, color: TextFieldColors.caret)) }
            }
            if let selection = node.selection, selection.length == 0, selection.location < positions.count {
                let p = positions[selection.location]
                primitives.append(.rect(Rect(x: originX + p.x, y: top + Float(p.line) * lineHeight, w: max(1, scale / 2), h: lineHeight), color: TextFieldColors.caret))
            }
        }
        if isFocused, isPlaceholder {
            primitives.append(.rect(Rect(x: originX, y: top, w: max(1, scale / 2), h: lineHeight), color: TextFieldColors.caret))
        }
        primitives.append(.clipPop)
        return primitives
    }
}
