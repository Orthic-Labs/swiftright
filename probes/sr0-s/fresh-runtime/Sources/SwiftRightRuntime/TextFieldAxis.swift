import Foundation

// Issue #60 pass 3 (F9): `TextField(_:text:axis: .vertical)`, the multi-line field.
//
// SwiftUI semantics on macOS: the field wraps its text at its width (the cell's content rect less the field editor's 2 pt line-fragment padding on each side: 6 pt in from each
// edge, where a single line starts) and is one line tall until the text needs more, then one `lineHeight` taller per line up to `.lineLimit(n)` (without a limit it grows
// without bound); past the limit the text scrolls inside the field. An empty or short field is the ordinary 24 pt bezel (8 pt of cell inset plus one 16 pt line). Return
// still submits (`onSubmit`); a line break comes from the field's text (a pasted newline) or Option-Return, which a host delivers as `insertLineBreak`. Not measured on macOS 27
// beyond the one-line frame (decision F9: 120 x 24); the growth numbers (8 pt + n x line height) follow from the cell inset and are checked by the `textfield-multiline` case.

/// A text field that can report its axis (`TextField` conforms).
protocol FieldAxisProviding {
    var fieldAxis: Axis { get }
}

extension TextField: @MainActor FieldAxisProviding {}

/// What a host needs to paint a vertical-axis TextField's wrapped text: the wrap width and the extent the shaped text measured at it (points).
public struct ResolvedVerticalField: Equatable, Sendable {
    /// The width the text wrapped at (the frame less 2 x the text origin).
    public let wrapWidth: Double
    /// The measured extent of the wrapped text (its widest line, all its lines).
    public let textWidth: Double
    public let textHeight: Double
    /// One line's height, and how many lines the text wrapped to.
    public let lineHeight: Double
    public let lines: Int
    /// `.lineLimit(n)` in effect (nil: unbounded).
    public let lineLimit: Int?

    public init(wrapWidth: Double, textWidth: Double, textHeight: Double, lineHeight: Double, lines: Int, lineLimit: Int?) {
        self.wrapWidth = wrapWidth; self.textWidth = textWidth; self.textHeight = textHeight
        self.lineHeight = lineHeight; self.lines = lines; self.lineLimit = lineLimit
    }

    /// The lines the field shows: the wrapped lines, at most `lineLimit`.
    public var visibleLines: Int { min(lines, max(1, lineLimit ?? lines)) }
}

public enum TextFieldAxisMetrics {
    /// The height of a vertical-axis field showing `lines` lines of `lineHeight` points in the bezeled style: the cell inset above and below plus the lines, never less than the
    /// single-line bezel; the plain style is the lines alone, never less than its one-line height.
    public static func height(artwork: TextFieldMetrics.Artwork, lines: Int, lineHeight: CGFloat) -> CGFloat {
        let n = CGFloat(max(1, lines))
        switch artwork {
        case .bezel: return max(TextFieldMetrics.bezelHeight, 2 * TextFieldMetrics.bezelTextInset + n * lineHeight)
        case .plain: return max(TextFieldMetrics.plainHeight, n * lineHeight)
        }
    }
}
