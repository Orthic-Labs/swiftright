import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// The default text face of a platform: what `Font.body` (a Text with no `.font`) measures with.
public struct BodyFontProfile: Equatable, Sendable {
    public var family: String
    public var weight: UInt32
    public var fontSizeDIP: Float
    public var lineHeightDIP: Float

    public init(family: String, weight: UInt32 = 400, fontSizeDIP: Float, lineHeightDIP: Float) {
        self.family = family; self.weight = weight; self.fontSizeDIP = fontSizeDIP; self.lineHeightDIP = lineHeightDIP
    }
    /// The live Windows message-font profile resolved by the runtime (DPI-aware).
    /// The line height follows SwiftUI/CoreText (round(hhea ascent) + round(hhea descent) of the resolved face) when the face's metrics
    /// could be read, else the GDI text-metric height; the renderer's baseline rule (round(ascent) from the line top) is the same rule.
    public init(_ native: NativeWindowsBodyFont) {
        self.init(family: native.family, weight: native.weight, fontSizeDIP: native.fontSizeDIP,
                  lineHeightDIP: native.coreTextLineHeightDIP ?? native.lineHeightDIP)
    }
}

/// Answers `Font.custom` names: the renderer family a bundled font was registered under and its vertical metrics.
public protocol CustomFontResolving: AnyObject {
    func providerFamily(forCustomName name: String) -> String?
    func metrics(forCustomName name: String) -> FontFileMetrics?
}

extension BundledFontLibrary: CustomFontResolving {}

/// The shaped run a Text node paints with (the retained measurement of its text at its resolved bounds).
@MainActor
public protocol TextRunSource: AnyObject {
    func run(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle
    /// The same run shaped in `color` (0xRRGGBBAA, baked into the shaped run by the renderer). Colour never changes the geometry.
    func run(text: String, font: Font?, bounds: Rect, color: UInt32) throws -> TextRunHandle
    /// The run of `text` at its natural (unwrapped) size in `color`, with that size and baseline in pixels: the retained measurement a
    /// TextField takes (its text is placed inside the field, so no resolved bounds name it). Nil when the source has no such measurement.
    func naturalRun(text: String, font: Font?, color: UInt32) throws -> NaturalTextRun?
    /// Per-character cells of a run (physical px, relative to the line start), for caret and selection geometry; empty when unavailable.
    func cells(of run: TextRunHandle) -> [CharCell]
}

/// A natural-size run: the handle and its pixel extent.
public struct NaturalTextRun {
    public let run: TextRunHandle
    public let width: Float, height: Float, baseline: Float
    public init(run: TextRunHandle, width: Float, height: Float, baseline: Float) {
        self.run = run; self.width = width; self.height = height; self.baseline = baseline
    }
}

extension TextRunSource {
    public func naturalRun(text: String, font: Font?, color: UInt32) throws -> NaturalTextRun? { nil }
    public func cells(of run: TextRunHandle) -> [CharCell] { [] }

    /// A source without per-run colour paints every run in its one colour.
    public func run(text: String, font: Font?, bounds: Rect, color: UInt32) throws -> TextRunHandle {
        try run(text: text, font: font, bounds: bounds)
    }
}

public enum TextMeasureError: Error, Equatable, CustomStringConvertible {
    case unsupportedFont(String)
    case unsupportedLineLimit(Int)
    case customFontNotBundled(String)
    case customFontMetricsUnavailable(String)
    case invalidPointSize
    case measurementCacheBound
    case sourceTooLong
    case invalidWidth
    case multilineWithoutBound
    case noCandidateFits

    public var description: String { "TextMeasure: \(self)" }
}

/// How one runtime text request becomes a bridge shaping request. Pure (no renderer), so every font rule is testable.
public enum TextRequestAdapter {
    /// `body` is the body profile, `fonts` answers `Font.custom` names (bundled fonts registered with the renderer).
    public static func shapingRequest(for request: TextMeasureRequest, body: BodyFontProfile, fonts: CustomFontResolving?,
                                      scale: Float, textColor: UInt32) throws -> MeasureRequest {
        if let limit = request.lineLimit, limit != 1 { throw TextMeasureError.unsupportedLineLimit(limit) }
        let maxWidth = Float(request.proposedWidth ?? 0) * scale
        guard let metadata = request.fontMetadata else {
            guard request.fontID == "body" || request.fontID == "textStyle.body" else { throw TextMeasureError.unsupportedFont(request.fontID) }
            return MeasureRequest(text: request.text, fontFamily: body.family, weight: body.weight, color: textColor,
                                  fontSize: body.fontSizeDIP, lineHeight: body.lineHeightDIP, scale: scale, maxWidth: maxWidth)
        }
        guard metadata.isCustom, let name = metadata.familyName else { throw TextMeasureError.unsupportedFont(request.fontID) }
        guard let pointSize = metadata.pointSize.map(Float.init), pointSize.isFinite, pointSize > 0, pointSize <= 512 else {
            throw TextMeasureError.invalidPointSize
        }
        guard let fonts, let family = fonts.providerFamily(forCustomName: name) else { throw TextMeasureError.customFontNotBundled(name) }
        guard let metrics = fonts.metrics(forCustomName: name) else { throw TextMeasureError.customFontMetricsUnavailable(name) }
        let lineHeight = metrics.lineHeight(pointSize: pointSize)
        guard lineHeight.isFinite, lineHeight > 0 else { throw TextMeasureError.customFontMetricsUnavailable(name) }
        let weight: UInt32
        switch metadata.weight ?? .regular {
        case .regular: weight = 400
        case .medium: weight = 500
        case .semibold: weight = 600
        case .bold: weight = 700
        }
        return MeasureRequest(text: request.text, fontFamily: family, weight: weight, color: textColor,
                              fontSize: pointSize, lineHeight: lineHeight, scale: scale, maxWidth: maxWidth)
    }
}

/// One-line text with `.lineLimit(1)`: the longest prefix plus an ellipsis that fits the width. The search is
/// logarithmically bounded; every rejected measurement is released by `release`, only the returned run stays with the caller.
public enum SingleLineText {
    public struct Selection<M> {
        public let displayText: String
        public let measurement: M
        public let candidateCount: Int
    }

    public static func select<M>(_ text: String, maxWidth: Float,
                                 measure: (String) throws -> M,
                                 width: (M) -> Float, lineCount: (M) -> Int, release: (M) -> Void) throws -> Selection<M> {
        guard maxWidth.isFinite, maxWidth >= 0 else { throw TextMeasureError.invalidWidth }
        // Bound traversal and allocation before materialising grapheme clusters.
        let boundedText = String(text.prefix(4097))
        guard boundedText.count <= 4096 else { throw TextMeasureError.sourceTooLong }
        let characters = Array(boundedText)
        var evaluations = 0
        let maxEvaluations = 128
        func candidate(_ prefixCount: Int) -> String { String(characters.prefix(prefixCount)) + "\u{2026}" }
        func fits(_ m: M) -> Bool { lineCount(m) == 1 && (maxWidth <= 0 || width(m) <= maxWidth) }
        func evaluate(_ value: String) throws -> M? {
            guard evaluations < maxEvaluations else { return nil }
            evaluations += 1
            let result = try measure(value)
            if fits(result) { return result }
            release(result)
            return nil
        }
        let original = try measure(text)
        evaluations += 1
        if fits(original) { return Selection(displayText: text, measurement: original, candidateCount: evaluations) }
        release(original)
        guard maxWidth > 0 else { throw TextMeasureError.multilineWithoutBound }
        guard !characters.isEmpty else { throw TextMeasureError.noCandidateFits }
        var low = 0
        var high = max(0, characters.count - 1)
        var best: (prefixCount: Int, measurement: M)?
        do {
            while low <= high && evaluations < maxEvaluations {
                let middle = low + (high - low) / 2
                if let result = try evaluate(candidate(middle)) {
                    if let old = best { release(old.measurement) }
                    best = (middle, result)
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
        } catch {
            if let best { release(best.measurement) }
            throw error
        }
        guard let best else { throw TextMeasureError.noCandidateFits }
        return Selection(displayText: candidate(best.prefixCount), measurement: best.measurement, candidateCount: evaluations)
    }
}

/// The retained-run choice: among measured requests of the same text and font, those whose measured physical extent can
/// have been snapped to the resolved bounds; all candidates must agree (else the run is ambiguous and refused).
enum RetainedRunChoice {
    struct Entry {
        let proposedWidth: CGFloat?
        let width: Float, height: Float, lines: Int, firstBaseline: Float
    }
    static func choose(_ entries: [Entry], bounds: Rect, scale: Float, text: String) throws -> Entry {
        let candidates = entries.filter {
            snappedExtentCanMatch($0.width, bounds.w, origin: bounds.x, scale: scale)
                && snappedExtentCanMatch($0.height, bounds.h, origin: bounds.y, scale: scale)
        }.sorted { ($0.proposedWidth ?? .infinity) < ($1.proposedWidth ?? .infinity) }
        guard let chosen = candidates.first else { throw HostPaintError.measuredRunGeometryMismatch(text) }
        guard candidates.allSatisfy({ $0.width == chosen.width && $0.height == chosen.height && $0.lines == chosen.lines && $0.firstBaseline == chosen.firstBaseline }) else {
            throw HostPaintError.ambiguousMeasuredRun(text)
        }
        return chosen
    }
}

/// Text measurement through the renderer bridge for the runtime (`TextMeasurer`) and the run lookup the painter paints with.
/// Measurements are retained by request until `releaseAll`; a measurement that cannot be made is recorded in `failures`
/// (and returns zero size) and the painter's run lookup then fails visibly: nothing is substituted.
@MainActor
public final class BridgeTextMeasurer: TextMeasurer, TextRunSource {
    public let bridge: Bridge
    public let scale: Float
    public let body: BodyFontProfile
    public let fonts: CustomFontResolving?
    public let textColor: UInt32
    public private(set) var failures: [String] = []
    private let log: (String) -> Void
    private struct ColouredKey: Hashable { let request: TextMeasureRequest; let color: UInt32 }
    private var retained: [TextMeasureRequest: SwiftRightBridge.TextMeasurement] = [:]
    private var coloured: [ColouredKey: SwiftRightBridge.TextMeasurement] = [:]
    private static let cacheBound = 256

    public init(bridge: Bridge, scale: Float, body: BodyFontProfile, fonts: CustomFontResolving? = nil,
                textColor: UInt32 = 0x1f1f1fff, log: @escaping (String) -> Void = { print($0) }) {
        self.bridge = bridge; self.scale = scale; self.body = body; self.fonts = fonts; self.textColor = textColor; self.log = log
    }

    /// Shapes `request` in `color` (the single-line search for `lineLimit(1)` included); the caller owns the returned run.
    private func shape(_ request: TextMeasureRequest, color: UInt32) throws -> SwiftRightBridge.TextMeasurement {
        let shaping = try TextRequestAdapter.shapingRequest(for: request, body: body, fonts: fonts, scale: scale, textColor: color)
        if request.lineLimit == 1 {
            let selection = try SingleLineText.select(request.text, maxWidth: shaping.maxWidth,
                measure: { candidate -> SwiftRightBridge.TextMeasurement in
                    var r = shaping; r.text = candidate
                    return try bridge.measure(r)
                },
                width: { $0.width }, lineCount: { $0.lineCount }, release: { _ = bridge.release($0.run) })
            log("TEXT_SINGLE_LINE originalUTF8=\(request.text.utf8.count) displayUTF8=\(selection.displayText.utf8.count) candidateCount=\(selection.candidateCount) maxWidthPX=\(shaping.maxWidth)")
            return selection.measurement
        }
        return try bridge.measure(shaping)
    }

    public func measure(_ request: TextMeasureRequest) -> SwiftRightRuntime.TextMeasurement {
        do {
            guard Float(request.scale) == scale else { throw TextMeasureError.unsupportedFont("scale \(request.scale) != \(scale)") }
            let result: SwiftRightBridge.TextMeasurement
            if let cached = retained[request] {
                result = cached
            } else {
                guard retained.count < Self.cacheBound else { throw TextMeasureError.measurementCacheBound }
                result = try shape(request, color: textColor)
                retained[request] = result
                let shaping = try TextRequestAdapter.shapingRequest(for: request, body: body, fonts: fonts, scale: scale, textColor: textColor)
                log("TEXT_MEASURE text=\(request.text) fontID=\(request.fontID) family=\(shaping.fontFamily) weight=\(shaping.weight) fontSizeDIP=\(shaping.fontSize) lineHeightDIP=\(shaping.lineHeight) proposedDIP=\(request.proposedWidth.map(String.init(describing:)) ?? "nil") widthPX=\(result.width) heightPX=\(result.height) firstBaselinePX=\(result.firstBaseline) lines=\(result.lineCount) lineLimit=\(request.lineLimit.map(String.init) ?? "nil") scale=\(scale)")
            }
            return SwiftRightRuntime.TextMeasurement(size: LayoutSize(width: CGFloat(result.width / scale), height: CGFloat(result.height / scale)),
                                                     baseline: CGFloat(result.firstBaseline / scale), lineCount: result.lineCount)
        } catch {
            failures.append("measure '\(request.text.prefix(40))' fontID=\(request.fontID): \(error)")
            return SwiftRightRuntime.TextMeasurement(size: .zero, baseline: 0, lineCount: 0)
        }
    }

    /// The retained shaped run for a Text node of the given resolved pixel bounds.
    public func run(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle {
        let fontID = font?.id ?? "body"
        let metadata = font?.metadata
        let matching = retained.filter { $0.key.text == text && $0.key.fontID == fontID && $0.key.fontMetadata == metadata && Float($0.key.scale) == scale }
        let entries = matching.map { RetainedRunChoice.Entry(proposedWidth: $0.key.proposedWidth, width: $0.value.width, height: $0.value.height,
                                                             lines: $0.value.lines.count, firstBaseline: $0.value.firstBaseline) }
        let chosen = try RetainedRunChoice.choose(entries, bounds: bounds, scale: scale, text: text)
        guard let source = matching.first(where: { $0.key.proposedWidth == chosen.proposedWidth && $0.value.width == chosen.width && $0.value.height == chosen.height }) else {
            throw HostPaintError.measuredRunGeometryMismatch(text)
        }
        log("TEXT_RETAINED_RUN text=\(text) widthPX=\(chosen.width) heightPX=\(chosen.height) snappedWidthPX=\(bounds.w) lines=\(chosen.lines) proposedDIP=\(chosen.proposedWidth.map(String.init(describing:)) ?? "nil")")
        return source.value.run
    }

    /// The retained run of `run(text:font:bounds:)` re-shaped in `color`: same text, font and width, so the same geometry. Retained per request and colour.
    public func run(text: String, font: Font?, bounds: Rect, color: UInt32) throws -> TextRunHandle {
        guard color != textColor else { return try run(text: text, font: font, bounds: bounds) }
        let fontID = font?.id ?? "body"
        let metadata = font?.metadata
        let matching = retained.filter { $0.key.text == text && $0.key.fontID == fontID && $0.key.fontMetadata == metadata && Float($0.key.scale) == scale }
        let entries = matching.map { RetainedRunChoice.Entry(proposedWidth: $0.key.proposedWidth, width: $0.value.width, height: $0.value.height,
                                                             lines: $0.value.lines.count, firstBaseline: $0.value.firstBaseline) }
        let chosen = try RetainedRunChoice.choose(entries, bounds: bounds, scale: scale, text: text)
        guard let source = matching.first(where: { $0.key.proposedWidth == chosen.proposedWidth && $0.value.width == chosen.width && $0.value.height == chosen.height }) else {
            throw HostPaintError.measuredRunGeometryMismatch(text)
        }
        let key = ColouredKey(request: source.key, color: color)
        if let hit = coloured[key] { return hit.run }
        guard coloured.count < Self.cacheBound else { throw TextMeasureError.measurementCacheBound }
        let result = try shape(source.key, color: color)
        guard result.width == chosen.width, result.height == chosen.height, result.lines.count == chosen.lines else {
            _ = bridge.release(result.run)
            throw HostPaintError.measuredRunGeometryMismatch(text)
        }
        coloured[key] = result
        log("TEXT_COLOURED_RUN text=\(text) colorRGBA=\(String(format: "%08x", color)) widthPX=\(result.width) heightPX=\(result.height)")
        return result.run
    }

    public func naturalRun(text: String, font: Font?, color: UInt32) throws -> NaturalTextRun? {
        let fontID = font?.id ?? "body"
        let metadata = font?.metadata
        guard let source = retained.first(where: { $0.key.text == text && $0.key.fontID == fontID && $0.key.fontMetadata == metadata
                                                    && Float($0.key.scale) == scale && $0.key.proposedWidth == nil && $0.key.lineLimit == nil }) else { return nil }
        let measured = source.value
        guard color != textColor else {
            return NaturalTextRun(run: measured.run, width: measured.width, height: measured.height, baseline: measured.firstBaseline)
        }
        let key = ColouredKey(request: source.key, color: color)
        if let hit = coloured[key] { return NaturalTextRun(run: hit.run, width: hit.width, height: hit.height, baseline: hit.firstBaseline) }
        guard coloured.count < Self.cacheBound else { throw TextMeasureError.measurementCacheBound }
        let result = try shape(source.key, color: color)
        coloured[key] = result
        return NaturalTextRun(run: result.run, width: result.width, height: result.height, baseline: result.firstBaseline)
    }

    public func cells(of run: TextRunHandle) -> [CharCell] { (try? bridge.cells(of: run)) ?? [] }

    public func releaseAll() {
        retained.values.forEach { _ = bridge.release($0.run) }
        retained.removeAll()
        coloured.values.forEach { _ = bridge.release($0.run) }
        coloured.removeAll()
    }
}
