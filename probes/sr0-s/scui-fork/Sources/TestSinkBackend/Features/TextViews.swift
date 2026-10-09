@_spi(Backends) import SwiftCrossUI

extension DummyBackend: BackendFeatures.TextViews {
    public func size(
        of text: String,
        whenDisplayedIn widget: Widget,
        proposedWidth: Int?,
        proposedHeight: Int?,
        environment: EnvironmentValues
    ) -> SIMD2<Int> {
        // SR0-S sink: log every measurement request (layout-memoization tests read this).
        measureRequests.append(text)
        return Self.textSize(
            of: text,
            displayedWith: environment.resolvedFont,
            proposedWidth: proposedWidth,
            proposedHeight: proposedHeight,
            lineLimit: environment.lineLimitSettings
        )
    }

    /// SR0-S sink measurer: fixed 8 pt advance per character, 16 pt lines, greedy word wrap.
    /// Identical to the fresh runtime's `FixedAdvanceTextMeasurer`, so both seeds see the same text.
    nonisolated static func textSize(
        of text: String,
        displayedWith font: Font.Resolved,
        proposedWidth: Int?,
        proposedHeight: Int?,
        lineLimit: LineLimit? = nil,
    ) -> SIMD2<Int> {
        let advance = 8
        let lineHeight = 16
        guard !text.isEmpty else { return .zero }
        guard let proposedWidth else { return SIMD2(advance * text.count, lineHeight) }
        let limit = proposedWidth / advance
        var lines: [Int] = []
        var current: Int? = nil
        for piece in text.split(separator: " ", omittingEmptySubsequences: false) {
            let n = piece.count
            if let c = current {
                if c + 1 + n <= limit { current = c + 1 + n } else { lines.append(c); current = n }
            } else {
                current = n
            }
        }
        if let current { lines.append(current) }
        var lineCount = lines.count
        if let lineLimit {
            lineCount = min(lineCount, lineLimit.limit)
            if lineLimit.reservesSpace { lineCount = max(lineCount, lineLimit.limit) }
        }
        return SIMD2(advance * (lines.max() ?? 0), lineHeight * lineCount)
    }

    public func createTextView() -> Widget {
        TextView()
    }

    public func updateTextView(
        _ textView: Widget,
        content: String,
        environment: EnvironmentValues
    ) {
        let textView = textView as! TextView
        textView.content = content
        textView.color = environment.suggestedForegroundColor.resolve(in: environment)
        textView.font = environment.resolvedFont
    }
}
