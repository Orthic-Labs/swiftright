import Foundation

// Issue #68 (MarkdownUI on SwiftRight): styled Text runs.
//
// A `Text` is one string with the environment's font and colour (a plain Text, unchanged), or an ordered list of runs, each with its own attributes. A Text becomes a list of
// runs when it is built from an `AttributedString`, joined with `+` to a styled Text, or given a Text-returning modifier (`bold()`, `italic()`, `underline()`, `kerning(_:)`, ...).
// `Text + Text` of two plain Texts stays one plain string. The resolved node of a styled Text carries `styledText` (the runs with fonts and colours resolved against the
// environment); a plain Text's `styledText` is nil, so its node is exactly what it was.
//
// Layout of several runs is the runtime's own greedy inline flow (`TextRunFlow`): every word and space is measured in its run's font through the measurer, lines break at
// spaces (a word is never split), and a line is as tall as its tallest run, aligned on the baselines. A single undecorated run is measured as one request instead, so a
// plain paragraph with one font wraps and truncates exactly as a plain Text does.

// MARK: - Resolved model

/// What a run's measurement depends on beyond its font (the font id does not carry them): italic, kern and tracking. Nil on a request that has none of them.
public struct TextRunStyle: Hashable, Sendable {
    public var italic: Bool
    /// Points added after every glyph (`Text.kerning(_:)`).
    public var kern: CGFloat
    /// Points added after every glyph (`Text.tracking(_:)`).
    public var tracking: CGFloat
    public init(italic: Bool = false, kern: CGFloat = 0, tracking: CGFloat = 0) {
        self.italic = italic; self.kern = kern; self.tracking = tracking
    }
    public var isDefault: Bool { !italic && kern == 0 && tracking == 0 }
}

/// An underline or strikethrough of a run. The pattern name is carried (`solid`, `dot`, `dash`, `dashDot`, `dashDotDot`); hosts draw every pattern solid.
public struct ResolvedTextLine: Hashable, Sendable {
    public let pattern: String
    /// Nil: the line takes the run's text colour.
    public let color: ResolvedColor?
    public init(pattern: String = "solid", color: ResolvedColor? = nil) { self.pattern = pattern; self.color = color }
}

/// One run of a styled Text with everything resolved against the environment of its node.
public struct ResolvedTextRun: Hashable, Sendable {
    /// The characters of the run, with `.textCase` applied.
    public var text: String
    /// The font the run draws with (the run's own, else the environment's, with the Text modifiers applied); nil is the default body font.
    public var font: Font?
    /// Nil: the colour the node would draw plain text with (its foreground style, else the default label colour).
    public var foreground: ResolvedColor?
    public var background: ResolvedColor?
    public var underline: ResolvedTextLine?
    public var strikethrough: ResolvedTextLine?
    /// Italic, kern and tracking; nil when none applies.
    public var style: TextRunStyle?
    /// Points the run sits above the baseline (negative: below).
    public var baselineOffset: CGFloat
    public var link: URL?

    public init(text: String, font: Font? = nil, foreground: ResolvedColor? = nil, background: ResolvedColor? = nil, underline: ResolvedTextLine? = nil,
                strikethrough: ResolvedTextLine? = nil, style: TextRunStyle? = nil, baselineOffset: CGFloat = 0, link: URL? = nil) {
        self.text = text; self.font = font; self.foreground = foreground; self.background = background; self.underline = underline
        self.strikethrough = strikethrough; self.style = style; self.baselineOffset = baselineOffset; self.link = link
    }

    /// True when the run draws something besides glyphs (a background, an underline, a strikethrough) or sits off the baseline.
    public var isDecorated: Bool { background != nil || underline != nil || strikethrough != nil || baselineOffset != 0 }

    /// True when this run alone can be measured and painted as one plain request (no decoration): its own font, colour, italic, kern and tracking only.
    public var isNative: Bool { !isDecorated }

    /// The measurement request of `text` (default: the run's own) in this run's font.
    public func measureRequest(text override: String? = nil, proposedWidth: CGFloat?, scale: CGFloat, lineLimit: Int?) -> TextMeasureRequest {
        let f = font ?? Font(id: "body")
        return TextMeasureRequest(text: override ?? text, fontID: f.id, proposedWidth: proposedWidth, scale: scale, fontMetadata: f.metadata, lineLimit: lineLimit,
                                  runStyle: style)
    }
}

/// The runs of a styled Text node and the `.lineLimit` in effect.
public struct ResolvedStyledText: Hashable, Sendable {
    public var runs: [ResolvedTextRun]
    public var lineLimit: Int?
    public init(runs: [ResolvedTextRun], lineLimit: Int? = nil) { self.runs = runs; self.lineLimit = lineLimit }
    /// One undecorated run: measured and painted as a single plain request (native wrapping and truncation).
    public var isNative: Bool { runs.count == 1 && runs[0].isNative }
}

/// A measurement of the runs of a styled Text.
public struct TextRunsMeasureRequest: Hashable, Sendable {
    public let runs: [ResolvedTextRun]
    public let proposedWidth: CGFloat?
    public let scale: CGFloat
    public let lineLimit: Int?
    public init(runs: [ResolvedTextRun], proposedWidth: CGFloat?, scale: CGFloat, lineLimit: Int?) {
        self.runs = runs; self.proposedWidth = proposedWidth; self.scale = scale; self.lineLimit = lineLimit
    }
}

// MARK: - Unresolved runs (what a Text holds)

/// One run of a Text before the environment is known: explicit attributes only. Nil/false means "inherit".
struct TextRun: Hashable, Sendable {
    var text: String
    var font: Font?
    var foreground: ResolvedColor?
    var background: ResolvedColor?
    var underline: ResolvedTextLine?
    var strikethrough: ResolvedTextLine?
    var kern: CGFloat?
    var tracking: CGFloat?
    var baselineOffset: CGFloat?
    var link: URL?
    // Text modifiers that edit whichever font the run ends up with (`Text.bold()` keeps working under a later `.font(_:)`).
    var bold = false
    var italic = false
    var monospaced = false
    var weight: Font.Weight?

    /// True when the run asks for anything of its own.
    var hasExplicitAttributes: Bool {
        var bare = self
        bare.text = ""
        return bare != TextRun(text: "")
    }

    func sameAttributes(as other: TextRun) -> Bool {
        var a = self, b = other
        a.text = ""; b.text = ""
        return a == b
    }

    /// The font this run draws with: its own (else `base`, the environment's) with weight, bold, monospaced and italic applied in that order.
    func resolvedFont(base: Font?) -> Font? {
        let chosen = font ?? base
        guard weight != nil || bold || monospaced || italic else { return chosen }
        var f = chosen ?? .body
        if let weight { f = f.weight(weight) }
        if bold { f = f.bold() }
        if monospaced { f = f.monospaced() }
        if italic { f = f.italic() }
        return f
    }

    @MainActor
    func resolved(base: Font?, environment: EnvironmentValues, textCase: Text.Case?) -> ResolvedTextRun {
        let f = resolvedFont(base: base)
        let style = TextRunStyle(italic: f?.isItalic ?? false, kern: kern ?? 0, tracking: tracking ?? 0)
        func tint(_ color: ResolvedColor?) -> ResolvedColor? { color?.resolvingTint(environment) }
        func line(_ value: ResolvedTextLine?) -> ResolvedTextLine? { value.map { ResolvedTextLine(pattern: $0.pattern, color: tint($0.color)) } }
        return ResolvedTextRun(text: textCase?.apply(text) ?? text, font: f, foreground: tint(foreground), background: tint(background), underline: line(underline),
                               strikethrough: line(strikethrough), style: style.isDefault ? nil : style, baselineOffset: baselineOffset ?? 0, link: link)
    }
}

extension Font {
    /// True when `italic()` was applied (the variant is carried in the id; the renderer draws it through the run's italic style).
    var isItalic: Bool { id.split(separator: "|").contains("italic") }
}

private func resolvedLine(_ style: Text.LineStyle) -> ResolvedTextLine {
    ResolvedTextLine(pattern: style.pattern.name, color: style.color?.resolvedColor)
}

// MARK: - Text API

extension Text {
    /// The runs of this Text, a plain Text being one run without attributes.
    var plainRuns: [TextRun] { runs ?? [TextRun(text: string)] }

    /// A Text of `runs`: empty runs dropped, neighbours with equal attributes merged; no runs is `Text("")`, and one run without attributes is a plain Text.
    static func normalized(_ runs: [TextRun]) -> Text {
        var merged: [TextRun] = []
        for run in runs where !run.text.isEmpty {
            if var last = merged.last, last.sameAttributes(as: run) {
                last.text += run.text
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        if merged.isEmpty { return Text("") }
        if merged.count == 1, !merged[0].hasExplicitAttributes { return Text(merged[0].text) }
        return Text(joined: merged.map(\.text).joined(), runs: merged)
    }

    private func edited(_ edit: (inout TextRun) -> Void) -> Text {
        var all = plainRuns
        for index in all.indices { edit(&all[index]) }
        return Text.normalized(all)
    }

    /// The characters of an attributed string, one run per attribute run: SwiftUI-scope font, foreground and background colour, underline and strikethrough style, kern, tracking,
    /// baseline offset, and the Foundation link. Attributes the runtime does not draw are dropped.
    /// Apple: https://developer.apple.com/documentation/swiftui/text/init(_:)-1jk6v
    public init(_ attributedContent: AttributedString) {
        var converted: [TextRun] = []
        for run in attributedContent.runs {
            var item = TextRun(text: String(attributedContent[run.range].characters))
            let attributes = run.attributes
            item.font = attributes[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
            item.foreground = attributes[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self]?.resolvedColor
            item.background = attributes[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self]?.resolvedColor
            item.underline = attributes[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self].map(resolvedLine)
            item.strikethrough = attributes[AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self].map(resolvedLine)
            item.kern = attributes[AttributeScopes.SwiftUIAttributes.KerningAttribute.self]
            item.tracking = attributes[AttributeScopes.SwiftUIAttributes.TrackingAttribute.self]
            item.baselineOffset = attributes[AttributeScopes.SwiftUIAttributes.BaselineOffsetAttribute.self]
            item.link = attributes[AttributeScopes.FoundationAttributes.LinkAttribute.self]
            // SwiftUI draws a linked run in the system link colour unless the run sets its own foreground colour (#74).
            if item.link != nil, item.foreground == nil { item.foreground = ResolvedColor.semantic("link") }
            converted.append(item)
        }
        self = Text.normalized(converted)
    }

    /// Joins two texts, keeping each one's runs. Two plain texts join into one plain string.
    /// Apple: https://developer.apple.com/documentation/swiftui/text/+(_:_:)
    public static func + (lhs: Text, rhs: Text) -> Text {
        if lhs.runs == nil && rhs.runs == nil { return Text(lhs.string + rhs.string) }
        return Text.normalized(lhs.plainRuns + rhs.plainRuns)
    }

    /// Bold weight for the characters (applied after the font, so it survives a later `.font(_:)`). `false` leaves the text unchanged.
    /// Apple: https://developer.apple.com/documentation/swiftui/text/bold(_:)
    public func bold(_ isActive: Bool = true) -> Text { isActive ? edited { $0.bold = true } : self }

    /// Apple: https://developer.apple.com/documentation/swiftui/text/italic(_:)
    public func italic(_ isActive: Bool = true) -> Text { isActive ? edited { $0.italic = true } : self }

    /// Apple: https://developer.apple.com/documentation/swiftui/text/monospaced(_:)
    public func monospaced(_ isActive: Bool = true) -> Text { isActive ? edited { $0.monospaced = true } : self }

    /// Apple: https://developer.apple.com/documentation/swiftui/text/fontweight(_:)
    public func fontWeight(_ weight: Font.Weight?) -> Text { edited { $0.weight = weight } }

    /// The font of runs that have none of their own (an `AttributedString` run's font wins). Disfavoured against `View.font(_:)`, so a Text used as a view keeps the environment
    /// modifier node it always had, and a Text that needs to stay a Text (`Text("a").font(.title) + Text("b")`) takes this overload.
    /// Apple: https://developer.apple.com/documentation/swiftui/text/font(_:)
    @_disfavoredOverload
    public func font(_ font: Font?) -> Text { edited { if $0.font == nil { $0.font = font } } }

    /// The colour of runs that have none of their own. Disfavoured against `View.foregroundColor(_:)` (see `font(_:)`).
    /// Apple: https://developer.apple.com/documentation/swiftui/text/foregroundcolor(_:)
    @_disfavoredOverload
    public func foregroundColor(_ color: Color?) -> Text {
        let resolved = color?.resolvedColor
        return edited { if $0.foreground == nil { $0.foreground = resolved } }
    }

    /// A colour style for runs that have none of their own; the runtime paints text in one colour, so a style is its colour. Disfavoured against `View.foregroundStyle(_:)`.
    /// Apple: https://developer.apple.com/documentation/swiftui/text/foregroundstyle(_:)
    @_disfavoredOverload
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        let resolved = style.resolvedColor
        return edited { if $0.foreground == nil { $0.foreground = resolved } }
    }

    /// Underlines runs that have no underline of their own. `false` leaves the text unchanged. Hosts draw every pattern as a solid line.
    /// Apple: https://developer.apple.com/documentation/swiftui/text/underline(_:pattern:color:)
    public func underline(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text {
        guard isActive else { return self }
        let line = ResolvedTextLine(pattern: pattern.name, color: color?.resolvedColor)
        return edited { if $0.underline == nil { $0.underline = line } }
    }

    /// Apple: https://developer.apple.com/documentation/swiftui/text/strikethrough(_:pattern:color:)
    public func strikethrough(_ isActive: Bool = true, pattern: LineStyle.Pattern = .solid, color: Color? = nil) -> Text {
        guard isActive else { return self }
        let line = ResolvedTextLine(pattern: pattern.name, color: color?.resolvedColor)
        return edited { if $0.strikethrough == nil { $0.strikethrough = line } }
    }

    /// Points added after every glyph, for runs that set no kerning of their own.
    /// Apple: https://developer.apple.com/documentation/swiftui/text/kerning(_:)
    public func kerning(_ kerning: CGFloat) -> Text { edited { if $0.kern == nil { $0.kern = kerning } } }

    /// Apple: https://developer.apple.com/documentation/swiftui/text/tracking(_:)
    public func tracking(_ tracking: CGFloat) -> Text { edited { if $0.tracking == nil { $0.tracking = tracking } } }

    /// Apple: https://developer.apple.com/documentation/swiftui/text/baselineoffset(_:)
    public func baselineOffset(_ baselineOffset: CGFloat) -> Text { edited { if $0.baselineOffset == nil { $0.baselineOffset = baselineOffset } } }
}

// MARK: - Inline flow

/// Width, height and first baseline of one measured piece of text, in points.
public struct TextFlowMetrics: Equatable, Sendable {
    public var width: CGFloat, height: CGFloat, baseline: CGFloat
    public init(width: CGFloat, height: CGFloat, baseline: CGFloat) { self.width = width; self.height = height; self.baseline = baseline }
}

/// A stretch of one run on one line: `x` from the line start, `y` the top of the fragment's own box from the block top (so the fragment's baseline is on the line's).
public struct TextFlowFragment: Equatable, Sendable {
    public var run: Int
    public var text: String
    public var line: Int
    public var x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, baseline: CGFloat
}

public struct TextFlowLine: Equatable, Sendable {
    public var top: CGFloat, height: CGFloat
    /// The line's baseline from its top.
    public var ascent: CGFloat
    public var width: CGFloat
    /// The line's fragments, as indices into `TextFlowLayout.fragments`.
    public var fragments: Range<Int>
}

public struct TextFlowLayout: Equatable, Sendable {
    public var fragments: [TextFlowFragment]
    public var lines: [TextFlowLine]
    public var width: CGFloat, height: CGFloat
    public var firstBaseline: CGFloat, lastBaseline: CGFloat
    /// True when `lineLimit` cut lines off (the last kept line ends in an ellipsis).
    public var truncated: Bool
}

/// Greedy inline layout of several runs. Pure: `measure` answers the size of a piece of text in the font of a run (by index), so the same algorithm serves the layout
/// (any measurer) and the painter (the renderer's measurements).
///
/// Rules: a newline ends a line (an empty line is as tall as a space in the run that holds the newline); a line breaks before a word that does not fit, at the spaces
/// around it (the spaces at the break are dropped, as are leading spaces on a wrapped line); a word is unbreakable even where it spans runs (`bold` + `ly`); a word wider
/// than the line stays whole on a line of its own; `lineLimit` drops the lines past it and ends the last with an ellipsis.
@MainActor
public enum TextRunFlow {
    private enum Kind { case word, space, newline }
    private struct Token { var run: Int; var text: String; var kind: Kind }
    private struct Placed { var token: Token; var x: CGFloat; var metrics: TextFlowMetrics }
    private struct CacheKey: Hashable { var run: Int; var text: String }

    private static func tokens(of runs: [ResolvedTextRun]) -> [Token] {
        var out: [Token] = []
        for (index, run) in runs.enumerated() {
            var current: Token?
            for ch in run.text {
                if ch.isNewline {
                    if let c = current { out.append(c); current = nil }
                    out.append(Token(run: index, text: "\n", kind: .newline))
                    continue
                }
                let kind: Kind = ch == " " || ch == "\t" ? .space : .word
                if var c = current, c.kind == kind {
                    c.text.append(ch)
                    current = c
                } else {
                    if let c = current { out.append(c) }
                    current = Token(run: index, text: String(ch), kind: kind)
                }
            }
            if let c = current { out.append(c) }
        }
        return out
    }

    public static func layout(runs: [ResolvedTextRun], maxWidth: CGFloat?, lineLimit: Int?, measure: (String, Int) -> TextFlowMetrics) -> TextFlowLayout {
        let empty = TextFlowLayout(fragments: [], lines: [], width: 0, height: 0, firstBaseline: 0, lastBaseline: 0, truncated: false)
        let all = tokens(of: runs)
        guard !all.isEmpty else { return empty }
        var cache: [CacheKey: TextFlowMetrics] = [:]
        func metrics(_ run: Int, _ text: String) -> TextFlowMetrics {
            let key = CacheKey(run: run, text: text)
            if let hit = cache[key] { return hit }
            let m = measure(text, run)
            cache[key] = m
            return m
        }

        var lines: [[Placed]] = []
        var fallbacks: [TextFlowMetrics?] = []
        var current: [Placed] = []
        var x: CGFloat = 0
        var atWrapStart = false

        func finishLine(fallback: TextFlowMetrics?) {
            while let last = current.last, last.token.kind == .space { current.removeLast() }
            lines.append(current)
            fallbacks.append(fallback)
            current = []
            x = 0
        }

        var index = 0
        while index < all.count {
            let token = all[index]
            switch token.kind {
            case .newline:
                finishLine(fallback: metrics(token.run, " "))
                atWrapStart = false
                index += 1
            case .space:
                index += 1
                if current.isEmpty && atWrapStart { continue }
                let m = metrics(token.run, token.text)
                current.append(Placed(token: token, x: x, metrics: m))
                x += m.width
            case .word:
                var end = index
                var group: [(Token, TextFlowMetrics)] = []
                while end < all.count, all[end].kind == .word {
                    group.append((all[end], metrics(all[end].run, all[end].text)))
                    end += 1
                }
                let total = group.reduce(CGFloat(0)) { $0 + $1.1.width }
                if let maxWidth, current.contains(where: { $0.token.kind == .word }), x + total > maxWidth + 0.01 {
                    finishLine(fallback: nil)
                    atWrapStart = true
                }
                for (word, m) in group {
                    current.append(Placed(token: word, x: x, metrics: m))
                    x += m.width
                }
                atWrapStart = false
                index = end
            }
        }
        if !current.isEmpty { finishLine(fallback: nil) }
        else if all.last?.kind == .newline { finishLine(fallback: metrics(all[all.count - 1].run, " ")) }

        var truncated = false
        if let lineLimit, lineLimit >= 1, lines.count > lineLimit {
            truncated = true
            lines = Array(lines.prefix(lineLimit))
            fallbacks = Array(fallbacks.prefix(lineLimit))
            var last = lines[lineLimit - 1]
            while let tail = last.last, tail.token.kind == .space { last.removeLast() }
            let run = last.last?.token.run ?? all[all.count - 1].run
            let m = metrics(run, "\u{2026}")
            let start = last.last.map { $0.x + $0.metrics.width } ?? 0
            last.append(Placed(token: Token(run: run, text: "\u{2026}", kind: .word), x: start, metrics: m))
            lines[lineLimit - 1] = last
        }

        var fragments: [TextFlowFragment] = []
        var out: [TextFlowLine] = []
        var top: CGFloat = 0
        var widest: CGFloat = 0
        for (lineIndex, placed) in lines.enumerated() {
            let boxes = placed.isEmpty ? [fallbacks[lineIndex] ?? TextFlowMetrics(width: 0, height: 0, baseline: 0)] : placed.map(\.metrics)
            let ascent = boxes.map(\.baseline).max() ?? 0
            let descent = boxes.map { $0.height - $0.baseline }.max() ?? 0
            let start = fragments.count
            var k = 0
            while k < placed.count {
                var j = k
                var text = ""
                while j < placed.count, placed[j].token.run == placed[k].token.run {
                    text += placed[j].token.text
                    j += 1
                }
                let first = placed[k], last = placed[j - 1]
                let run = first.token.run
                fragments.append(TextFlowFragment(run: run, text: text, line: lineIndex, x: first.x, y: top + ascent - first.metrics.baseline - runs[run].baselineOffset,
                                                  width: last.x + last.metrics.width - first.x, height: first.metrics.height, baseline: first.metrics.baseline))
                k = j
            }
            let width = placed.last.map { $0.x + $0.metrics.width } ?? 0
            out.append(TextFlowLine(top: top, height: ascent + descent, ascent: ascent, width: width, fragments: start..<fragments.count))
            widest = max(widest, width)
            top += ascent + descent
        }
        guard let first = out.first, let last = out.last else { return empty }
        return TextFlowLayout(fragments: fragments, lines: out, width: widest, height: top, firstBaseline: first.ascent, lastBaseline: last.top + last.ascent, truncated: truncated)
    }
}

// MARK: - Measuring runs

extension TextMeasurer {
    /// The flow of `runs`, each word and space measured in its run's font by this measurer.
    public func flow(runs: [ResolvedTextRun], maxWidth: CGFloat?, lineLimit: Int?, scale: CGFloat) -> TextFlowLayout {
        TextRunFlow.layout(runs: runs, maxWidth: maxWidth, lineLimit: lineLimit) { text, index in
            let m = self.measure(runs[index].measureRequest(text: text, proposedWidth: nil, scale: scale, lineLimit: nil))
            return TextFlowMetrics(width: m.size.width, height: m.size.height, baseline: m.baseline)
        }
    }

    /// The flow a node of `frameWidth` points shows: the frame is the widest line, so a pixel of snapping slack keeps the layout's own breaks.
    public func flow(_ styled: ResolvedStyledText, frameWidth: CGFloat, scale: CGFloat) -> TextFlowLayout {
        flow(runs: styled.runs, maxWidth: frameWidth + 1 / max(scale, 1), lineLimit: styled.lineLimit, scale: scale)
    }

    /// The size, first baseline and line count of a styled Text. One undecorated run is one plain request (native wrapping and truncation); several runs, or a decorated run,
    /// are flowed word by word.
    public func measureRuns(_ request: TextRunsMeasureRequest) -> TextMeasurement {
        guard let only = request.runs.first else { return TextMeasurement(size: .zero, baseline: 0, lineCount: 0) }
        if request.runs.count == 1, only.isNative {
            return measure(only.measureRequest(proposedWidth: request.proposedWidth, scale: request.scale, lineLimit: request.lineLimit))
        }
        let layout = flow(runs: request.runs, maxWidth: request.proposedWidth, lineLimit: request.lineLimit, scale: request.scale)
        guard !layout.lines.isEmpty else { return TextMeasurement(size: .zero, baseline: 0, lineCount: 0) }
        return TextMeasurement(size: LayoutSize(width: layout.width, height: layout.height), baseline: layout.firstBaseline, lineCount: layout.lines.count,
                               lastBaseline: layout.lastBaseline)
    }
}

// MARK: - Graph integration

extension Graph {
    /// The resolved runs of a Text node that has them; nil for a plain Text and for every other node.
    func styledText(of node: Node) -> ResolvedStyledText? {
        guard case .text = node.kind, let text = node.view as? Text, let runs = text.runs else { return nil }
        let environment = node.environment
        let base = environment.textFont
        let textCase = environment.textCase
        return ResolvedStyledText(runs: runs.map { $0.resolved(base: base, environment: environment, textCase: textCase) }, lineLimit: environment.lineLimit)
    }

    /// Size of a styled Text for a (finite or nil) wrap width, memoised on the node like a plain Text (`wrapWidth` is nil when the proposal is unbounded).
    func measureStyledText(_ node: Node, _ styled: ResolvedStyledText, wrapWidth: CGFloat?) -> LayoutSize {
        let key = "\u{1}styled:\(styled.hashValue)"
        if node.memoText != key || node.memoLineLimit != styled.lineLimit {
            node.memoText = key
            node.memoFont = nil
            node.memoLineLimit = styled.lineLimit
            node.memoScaleFactor = 1
            node.memo.removeAll()
            node.memoBase.removeAll()
            node.memoScaledFont.removeAll()
        }
        if let cached = node.memo[wrapWidth] { return cached }
        let measured = measurer.measureRuns(TextRunsMeasureRequest(runs: styled.runs, proposedWidth: wrapWidth, scale: scale, lineLimit: styled.lineLimit))
        // As a plain Text: never wider than offered.
        let size = wrapWidth.map { LayoutSize(width: min(measured.size.width, max(0, $0)), height: measured.size.height) } ?? measured.size
        node.memo[wrapWidth] = size
        let lineHeight = measured.lineCount > 0 ? measured.size.height / CGFloat(measured.lineCount) : 0
        node.memoBase[wrapWidth] = (measured.baseline, measured.lastBaseline ?? (measured.baseline + CGFloat(max(0, measured.lineCount - 1)) * lineHeight))
        return size
    }

    /// A signature of a Text's runs for the layout cache (`LayoutKey`): equal runs, equal signature within a process.
    func styledLayoutSignature(of node: Node) -> String? {
        guard let runs = (node.view as? Text)?.runs else { return nil }
        return "\u{1}\(runs.hashValue)"
    }

    /// The link under (x, y) in logical points: the deepest Text node with a link run there, with the URL of that run.
    func linkTarget(atX x: CGFloat, y: CGFloat) -> (node: Node, url: URL)? {
        var best: (node: Node, url: URL, depth: Int)?
        func walk(_ n: Node, _ depth: Int) {
            guard n.alive else { return }
            if case .text = n.kind, n.environment.allowsHitTesting, n.environment.isEnabled,
               x >= n.frame.minX, x < n.frame.maxX, y >= n.frame.minY, y < n.frame.maxY,
               let styled = styledText(of: n), styled.runs.contains(where: { $0.link != nil }),
               let url = link(in: styled, frame: n.frame, x: x, y: y), best == nil || depth >= best!.depth {
                best = (n, url, depth)
            }
            for c in childNodes(n) { walk(c, depth + 1) }
        }
        if let root { walk(root, 0) }
        return best.map { ($0.node, $0.url) }
    }

    private func link(in styled: ResolvedStyledText, frame: LayoutRect, x: CGFloat, y: CGFloat) -> URL? {
        if styled.runs.count == 1 { return styled.runs[0].link }
        let layout = measurer.flow(styled, frameWidth: frame.width, scale: scale)
        let lx = x - frame.minX, ly = y - frame.minY
        for line in layout.lines where ly >= line.top && ly < line.top + line.height {
            for fragment in layout.fragments[line.fragments] where lx >= fragment.x && lx < fragment.x + fragment.width {
                return styled.runs[fragment.run].link
            }
        }
        return nil
    }

    /// A press released at (x, y) on a link run opens its URL through the node's `openURL` environment action. Returns whether a link was there.
    @discardableResult
    func openLink(atX x: CGFloat, y: CGFloat) -> Bool {
        guard let (node, url) = linkTarget(atX: x, y: y) else { return false }
        node.environment.openURL.perform(url)
        flush()
        return true
    }
}
