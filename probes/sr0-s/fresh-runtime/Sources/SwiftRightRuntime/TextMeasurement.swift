import Foundation

/// One synchronous measurement request. `proposedWidth` is nil when the text does not wrap.
public struct TextMeasureRequest: Hashable, Sendable {
    public let text: String
    public let fontID: String
    /// Optional descriptor for explicit system designs and custom families. Legacy requests leave it nil.
    public let fontMetadata: Font.Metadata?
    public let proposedWidth: CGFloat?
    public let scale: CGFloat

    public init(text: String, fontID: String, proposedWidth: CGFloat?, scale: CGFloat, fontMetadata: Font.Metadata? = nil) {
        self.text = text
        self.fontID = fontID
        self.fontMetadata = fontMetadata
        self.proposedWidth = proposedWidth
        self.scale = scale
    }
}

/// Measured text in logical points. `baseline` is measured from the top of the first line.
public struct TextMeasurement: Equatable, Sendable {
    public let size: LayoutSize
    public let baseline: CGFloat
    public let lineCount: Int

    public init(size: LayoutSize, baseline: CGFloat, lineCount: Int) {
        self.size = size
        self.baseline = baseline
        self.lineCount = lineCount
    }
}

/// Synchronous, read-only text measurement. Implementations must not call back into the graph.
@MainActor
public protocol TextMeasurer: AnyObject {
    func measure(_ request: TextMeasureRequest) -> TextMeasurement
}

/// Deterministic measurer for headless runs and tests: a fixed advance per character and greedy
/// word wrapping at the proposed width. A word wider than the proposal stays on its own line.
@MainActor
public final class FixedAdvanceTextMeasurer: TextMeasurer {
    public let advance: CGFloat
    public let lineHeight: CGFloat
    public private(set) var requests: [TextMeasureRequest] = []

    public init(advance: CGFloat = 8, lineHeight: CGFloat = 16) {
        self.advance = advance
        self.lineHeight = lineHeight
    }

    public func measure(_ request: TextMeasureRequest) -> TextMeasurement {
        requests.append(request)
        let lines = wrap(request.text, width: request.proposedWidth)
        guard !lines.isEmpty else {
            return TextMeasurement(size: .zero, baseline: 0, lineCount: 0)
        }
        let widest = lines.map { CGFloat($0.count) * advance }.max() ?? 0
        return TextMeasurement(
            size: LayoutSize(width: widest, height: CGFloat(lines.count) * lineHeight),
            baseline: lineHeight * 0.75,
            lineCount: lines.count
        )
    }

    /// Number of measurer calls whose text equals `text`.
    public func callCount(for text: String) -> Int {
        requests.filter { $0.text == text }.count
    }

    /// Hard line breaks first (a newline always starts a line, as in Text and TextEditor), then word wrap.
    private func wrap(_ text: String, width: CGFloat?) -> [String] {
        guard !text.isEmpty else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).flatMap { wrapLine(String($0), width: width) }
    }

    private func wrapLine(_ line: String, width: CGFloat?) -> [String] {
        guard let width else { return [line] }
        let limit = Int((width / advance).rounded(.down))
        var lines: [String] = []
        var current = ""
        for piece in line.split(separator: " ", omittingEmptySubsequences: false) {
            let word = String(piece)
            if current.isEmpty {
                current = word
            } else if current.count + 1 + word.count <= limit {
                current += " " + word
            } else {
                lines.append(current)
                current = word
            }
        }
        lines.append(current)
        return lines
    }
}
