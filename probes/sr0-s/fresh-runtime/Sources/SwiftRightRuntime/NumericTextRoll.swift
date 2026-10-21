import Foundation

// Issue #55: `.contentTransition(.numericText())` rolls the changed glyphs of a Text inside an animation transaction.
//
// Semantics (what SwiftUI does that is carried, and what is not measured):
// - Without an animation transaction the text swaps at once (the roll never starts).
// - Inside one, the old and new strings are aligned from their trailing ends (place value: 9 -> 10 pairs the 9 with the 0 and brings the 1 in). A glyph that is the
//   same in both stays and slides to its new place; a glyph that changed leaves (moves one line box up and fades out) while its replacement comes from one line box
//   below and fades in. `numericText(countsDown: true)` reverses the direction, and `numericText(value:)` counts down when the value fell since the last change.
//   A glyph that has no partner (the string grew or shrank) enters or leaves the same way. Each glyph is clipped to the Text's line box by the host.
// - The roll is a presented channel of the node (`PaintValues.roll`): it follows the transaction's animation like any other presented value, so a spring overshoot is
//   clamped to the end positions and an interrupting change restarts the roll from the glyphs the node was showing.
// - UNMEASURED: SwiftUI's exact travel distance and fade curves. The runtime uses one line height and a linear fade of both glyphs in the layer's progress; the
//   factory case `numeric-text-v1` has the mid frame a Mac comparison decides this from.
// - A Text that wraps, truncates, has several lines or is made of styled runs swaps at once.

/// One glyph of a rolling numeric Text: where it is relative to the node's frame origin (points) and how opaque.
public struct ResolvedNumericGlyph: Equatable, Sendable {
    public let text: String
    public let x: CGFloat
    /// Offset from the baseline position of an unmoved glyph: negative is up.
    public let y: CGFloat
    public let opacity: Double
    public init(text: String, x: CGFloat, y: CGFloat, opacity: Double) { self.text = text; self.x = x; self.y = y; self.opacity = opacity }
}

/// What the host paints for a numeric Text mid-roll instead of its string: the glyphs, each clipped to the node's line box vertically.
public struct ResolvedNumericRoll: Equatable, Sendable {
    public let glyphs: [ResolvedNumericGlyph]
    /// 0 (the old text) ... 1 (the new text).
    public let progress: Double
    public let countsDown: Bool
    public init(glyphs: [ResolvedNumericGlyph], progress: Double, countsDown: Bool) { self.glyphs = glyphs; self.progress = progress; self.countsDown = countsDown }
}

/// Per-node roll state: the last text the node showed as a target and how many changes it has seen.
struct NumericRollState {
    var text: String
    var serial = 0
    /// The text before the latest change.
    var from: String
    /// The presented roll value when the latest change happened (`serial - 1` unless it interrupted a roll).
    var start = 0.0
    var countsDown = false
    var value: Double?
    var offsetsCache: [String: [CGFloat]] = [:]
}

extension ContentTransition {
    var isNumericText: Bool { name == "numericText" }
}

extension Graph {
    /// Tracks a Text's displayed string under a numeric-text transition; every change moves the node's roll counter (an animatable paint component).
    func updateNumericRoll(_ node: Node) {
        guard case .text(let raw) = node.kind else { return }
        let transition = node.environment.contentTransition
        guard transition.isNumericText else {
            node.numericRoll = nil
            return
        }
        let string = node.environment.textCase?.apply(raw) ?? raw
        guard var state = node.numericRoll else {
            node.numericRoll = NumericRollState(text: string, from: string, value: transition.value)
            return
        }
        if state.text != string {
            state.from = state.text
            state.text = string
            state.serial += 1
            state.start = node.presentedPaint?.roll ?? Double(state.serial - 1)
            if let new = transition.value, let old = state.value { state.countsDown = new < old } else { state.countsDown = transition.countsDown }
            state.offsetsCache.removeAll()
        }
        state.value = transition.value
        node.numericRoll = state
    }

    /// The glyphs of a rolling Text at the node's presented progress; nil when it is not rolling or cannot roll.
    func resolveNumericRoll(_ node: Node, style: ResolvedStyle, text: String?) -> ResolvedNumericRoll? {
        guard var state = node.numericRoll, state.serial > 0, let presented = node.presentedPaint?.roll else { return nil }
        let end = Double(state.serial)
        guard presented < end, end - state.start > 0 else { return nil }
        guard styledText(of: node) == nil, let newText = text, newText == state.text, !newText.contains("\n"), !state.from.contains("\n") else { return nil }
        let progress = min(max((presented - state.start) / (end - state.start), 0), 1)
        let font = style.font ?? Font(id: "body")
        func offsets(_ string: String) -> [CGFloat] {
            let key = "\(font.id)|\(string)"
            if let cached = state.offsetsCache[key] { return cached }
            let chars = Array(string)
            var out: [CGFloat] = []
            for i in 0...chars.count {
                let prefix = String(chars.prefix(i))
                out.append(i == 0 ? 0 : measurer.measure(TextMeasureRequest(text: prefix, fontID: font.id, proposedWidth: nil, scale: scale, fontMetadata: font.metadata)).size.width)
            }
            state.offsetsCache[key] = out
            return out
        }
        let oldChars = Array(state.from), newChars = Array(newText)
        let oldX = offsets(state.from), newX = offsets(newText)
        // a Text that would wrap or truncate swaps at once
        if (newX.last ?? 0) > node.frame.width + 0.5 { node.numericRoll = state; return nil }
        node.numericRoll = state
        let h = node.frame.height
        let down: CGFloat = state.countsDown ? -1 : 1
        let p = CGFloat(progress)
        let outY = -down * h * p, inY = down * h * (1 - p)
        var glyphs: [ResolvedNumericGlyph] = []
        for k in stride(from: max(oldChars.count, newChars.count) - 1, through: 0, by: -1) {
            let oi = oldChars.count - 1 - k, ni = newChars.count - 1 - k
            switch (oi >= 0, ni >= 0) {
            case (true, true):
                let x = oldX[oi] + (newX[ni] - oldX[oi]) * p
                if oldChars[oi] == newChars[ni] {
                    glyphs.append(ResolvedNumericGlyph(text: String(newChars[ni]), x: x, y: 0, opacity: 1))
                } else {
                    glyphs.append(ResolvedNumericGlyph(text: String(oldChars[oi]), x: x, y: outY, opacity: 1 - progress))
                    glyphs.append(ResolvedNumericGlyph(text: String(newChars[ni]), x: x, y: inY, opacity: progress))
                }
            case (true, false):
                glyphs.append(ResolvedNumericGlyph(text: String(oldChars[oi]), x: oldX[oi], y: outY, opacity: 1 - progress))
            case (false, true):
                glyphs.append(ResolvedNumericGlyph(text: String(newChars[ni]), x: newX[ni], y: inY, opacity: progress))
            default: break
            }
        }
        return ResolvedNumericRoll(glyphs: glyphs, progress: progress, countsDown: state.countsDown)
    }
}
