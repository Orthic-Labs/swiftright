import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// The default text face of a platform: what `Font.body` (a Text with no `.font`) measures with.
public struct BodyFontProfile: Equatable, Sendable {
    public var family: String
    public var weight: UInt32
    public var fontSizeDIP: Float
    public var lineHeightDIP: Float
    /// The face's hhea ascent and descent in em (read from the face when the platform can); nil derives a line height by scaling `lineHeightDIP`.
    public var ascentEm: Float?
    public var descentEm: Float?

    public init(family: String, weight: UInt32 = 400, fontSizeDIP: Float, lineHeightDIP: Float, ascentEm: Float? = nil, descentEm: Float? = nil) {
        self.family = family; self.weight = weight; self.fontSizeDIP = fontSizeDIP; self.lineHeightDIP = lineHeightDIP
        self.ascentEm = ascentEm; self.descentEm = descentEm
    }

    /// The SwiftUI/CoreText line height of this face at `size` DIP: round(ascent) + round(descent) (the rule `NativeWindowsBodyFont.coreTextLineHeightDIP` applies at the body
    /// size). Without face metrics the body line height is scaled by the size ratio.
    public func lineHeight(forSize size: Float) -> Float {
        if let a = ascentEm, let d = descentEm { return (size * a).rounded() + (size * d).rounded() }
        return (lineHeightDIP * size / fontSizeDIP).rounded()
    }
    /// The live Windows message-font profile resolved by the runtime (DPI-aware).
    /// The line height follows SwiftUI/CoreText (round(hhea ascent) + round(hhea descent) of the resolved face) when the face's metrics
    /// could be read, else the GDI text-metric height; the renderer's baseline rule (round(ascent) from the line top) is the same rule.
    public init(_ native: NativeWindowsBodyFont) {
        var asc: Float?, desc: Float?
        if let upm = native.unitsPerEm, upm > 0, let a = native.hheaAscentUnits, let d = native.hheaDescentUnits {
            asc = Float(a) / Float(upm); desc = abs(Float(d)) / Float(upm)
        }
        self.init(family: native.family, weight: native.weight, fontSizeDIP: native.fontSizeDIP,
                  lineHeightDIP: native.coreTextLineHeightDIP ?? native.lineHeightDIP, ascentEm: asc, descentEm: desc)
    }
}

/// Answers `Font.custom` names: the renderer family a bundled font was registered under and its vertical metrics.
public protocol CustomFontResolving: AnyObject {
    func providerFamily(forCustomName name: String) -> String?
    func metrics(forCustomName name: String) -> FontFileMetrics?
    /// The weight class a custom name selects by itself (`Tinos-Bold` is 700); nil for a family name. Defaults to nil for a resolver that does not know faces.
    func weight(forCustomName name: String) -> UInt32?
}

extension CustomFontResolving {
    public func weight(forCustomName name: String) -> UInt32? { nil }
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
    /// True when the retained run for these bounds is wider than the frame the runtime gave it (a Text offered less than its glyphs need): the painter then clips the run to the frame.
    func runOverflows(text: String, font: Font?, bounds: Rect) -> Bool
    /// `run(text:font:bounds:)` for a styled-Text run (#68): its italic, kern and tracking are part of the request. `color` nil keeps the source's own colour.
    func run(text: String, font: Font?, style: TextRunStyle?, bounds: Rect, color: UInt32?) throws -> TextRunHandle
    func runOverflows(text: String, font: Font?, style: TextRunStyle?, bounds: Rect) -> Bool
    /// The retained shaped run of one fragment of a styled Text (one line's stretch of one run), at its natural size: measured on first use. Nil when the source has none.
    func fragmentRun(text: String, font: Font?, style: TextRunStyle?, color: UInt32?) throws -> NaturalTextRun?
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
    public func runOverflows(text: String, font: Font?, bounds: Rect) -> Bool { false }

    /// A source that does not know run styles shapes the run without them.
    public func run(text: String, font: Font?, style: TextRunStyle?, bounds: Rect, color: UInt32?) throws -> TextRunHandle {
        if let color { return try run(text: text, font: font, bounds: bounds, color: color) }
        return try run(text: text, font: font, bounds: bounds)
    }
    public func runOverflows(text: String, font: Font?, style: TextRunStyle?, bounds: Rect) -> Bool { runOverflows(text: text, font: font, bounds: bounds) }
    public func fragmentRun(text: String, font: Font?, style: TextRunStyle?, color: UInt32?) throws -> NaturalTextRun? { nil }

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
    /// The F1 metric table was measured at scale 1 and 2.5 only (G21).
    case unsupportedScale(Float)
    /// The F1 table has no row for this system font (size outside 9 to 40 pt in half points, or a scale it lacks).
    case systemFontMetricsUnavailable(String)

    /// Spelled out case by case: interpolating `self` here would call `description` again and overflow the stack on the first failure.
    public var description: String {
        switch self {
        case .unsupportedFont(let id): return "TextMeasure: unsupportedFont(\(id))"
        case .unsupportedLineLimit(let n): return "TextMeasure: unsupportedLineLimit(\(n))"
        case .customFontNotBundled(let name): return "TextMeasure: customFontNotBundled(\(name))"
        case .customFontMetricsUnavailable(let name): return "TextMeasure: customFontMetricsUnavailable(\(name))"
        case .invalidPointSize: return "TextMeasure: invalidPointSize"
        case .measurementCacheBound: return "TextMeasure: measurementCacheBound"
        case .sourceTooLong: return "TextMeasure: sourceTooLong"
        case .invalidWidth: return "TextMeasure: invalidWidth"
        case .multilineWithoutBound: return "TextMeasure: multilineWithoutBound"
        case .noCandidateFits: return "TextMeasure: noCandidateFits"
        case .unsupportedScale(let s): return "TextMeasure: unsupportedScale(\(s)) (the Mac metric table is measured at scale 1 and 2.5)"
        case .systemFontMetricsUnavailable(let what): return "TextMeasure: systemFontMetricsUnavailable(\(what))"
        }
    }
}

/// How one runtime text request becomes a bridge shaping request. Pure (no renderer), so every font rule is testable.
public enum TextRequestAdapter {
    /// `body` is the legacy body profile (kept for callers; system fonts no longer read it: the body is 13 DIP from the Mac table, G40), `fonts` answers `Font.custom`
    /// names (bundled fonts registered with the renderer). The returned request carries the 0.7 fields; `plan(for:)` carries the rest.
    public static func shapingRequest(for request: TextMeasureRequest, body: BodyFontProfile, fonts: CustomFontResolving?,
                                      scale: Float, textColor: UInt32, systemFonts: SystemFontMapper = SystemFontMapper()) throws -> MeasureRequest {
        if let limit = request.lineLimit, limit < 1 { throw TextMeasureError.unsupportedLineLimit(limit) }
        let maxWidth = Float(request.proposedWidth ?? 0) * scale
        if let plan = try systemPlan(for: request, scale: scale, systemFonts: systemFonts) {
            return MeasureRequest(text: request.text, fontFamily: plan.family, weight: plan.weight, color: textColor,
                                  fontSize: plan.sizeDIP, lineHeight: plan.linePitchDIP, scale: scale, maxWidth: maxWidth)   // the Mac pitch: the renderer rounds the block once (G75b)
        }
        guard let metadata = request.fontMetadata, metadata.isCustom, let name = metadata.familyName else { throw TextMeasureError.unsupportedFont(request.fontID) }
        guard let pointSize = metadata.pointSize.map(Float.init), pointSize.isFinite, pointSize > 0, pointSize <= 512 else {
            throw TextMeasureError.invalidPointSize
        }
        guard let fonts, let family = fonts.providerFamily(forCustomName: name) else { throw TextMeasureError.customFontNotBundled(name) }
        guard let metrics = fonts.metrics(forCustomName: name) else { throw TextMeasureError.customFontMetricsUnavailable(name) }
        let lineHeight = metrics.lineHeight(pointSize: pointSize)
        guard lineHeight.isFinite, lineHeight > 0 else { throw TextMeasureError.customFontMetricsUnavailable(name) }
        return MeasureRequest(text: request.text, fontFamily: family, weight: metadata.weight?.classValue ?? fonts.weight(forCustomName: name) ?? Font.Weight.regular.classValue, color: textColor,
                              fontSize: pointSize, lineHeight: lineHeight, scale: scale, maxWidth: maxWidth)
    }

    /// The system-font plan of a request (the body font when it has no font; `Font.system`; a text style), nil for a custom font. Decision G70: the Mac metric table is the source
    /// of line height and baseline for every system size and style.
    public static func systemPlan(for request: TextMeasureRequest, scale: Float, systemFonts: SystemFontMapper = SystemFontMapper()) throws -> SystemFontPlan? {
        guard let metadata = request.fontMetadata else {
            guard request.fontID == "body" || request.fontID == "textStyle.body" else { throw TextMeasureError.unsupportedFont(request.fontID) }
            return try systemFonts.plan(for: nil, scale: scale)
        }
        if metadata.isCustom { return nil }
        return try systemFonts.plan(for: metadata, scale: scale)
    }

    /// The request extension of a custom (bundled) font under ABI 0.8: kerning on, no synthesis (G27); the renderer's own baseline rule (matches CoreText over the file's
    /// metrics: Tinos 17 of 22 at 20 pt, E14c).
    public static var customExtension: TextExtension { TextExtension(features: [.kern], simulations: .forbidAll) }
}

/// `.lineLimit(n)` through the renderer's own truncation (additive ABI flag SWR_M08_MAX_LINES, #51): one request carries the limit, the renderer ends the
/// text in a fitting ellipsis, and measure and paint (both shape through the same call) agree. The host-side prefix search (`SingleLineText`) is only the
/// fallback when the renderer cannot or did not apply the flag (an older renderer), so a limit is never silently dropped.
public enum NativeLineLimit {
    public static let maxSupported = 1000

    /// The request with the limit set, or nil when the limit cannot go native (outside 1...1000).
    public static func request(_ shaping: MeasureRequest, limit: Int) -> MeasureRequest? {
        guard (1...maxSupported).contains(limit) else { return nil }
        var r = shaping; r.maxLines = limit
        return r
    }

    /// Native first; the fallback runs when the renderer has no 0.8 text extension, the limit is out of range, the native request is refused, or the result does not
    /// report SWR_M08_APPLIED_MAX_LINES (the rejected measurement is released first).
    public static func shape<M>(_ shaping: MeasureRequest, limit: Int, rendererSupportsMaxLines: Bool,
                                native: (MeasureRequest) throws -> M, applied: (M) -> Bool, release: (M) -> Void,
                                fallback: () throws -> M) rethrows -> (measurement: M, native: Bool) {
        if rendererSupportsMaxLines, let r = request(shaping, limit: limit), let result = try? native(r) {
            if applied(result) { return (result, true) }
            release(result)
        }
        return (try fallback(), false)
    }
}

/// Text with `.lineLimit(n)`: the longest prefix plus an ellipsis that fits the width in at most `n` lines (n = 1: one line). The search is
/// logarithmically bounded; every rejected measurement is released by `release`, only the returned run stays with the caller.
public enum SingleLineText {
    public struct Selection<M> {
        public let displayText: String
        public let measurement: M
        public let candidateCount: Int
    }

    public static func select<M>(_ text: String, maxWidth: Float, lineLimit: Int = 1,
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
        func fits(_ m: M) -> Bool { lineCount(m) >= 1 && lineCount(m) <= lineLimit && (maxWidth <= 0 || width(m) <= maxWidth) }
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

/// Float renderer values to the layout's Double DIP without Float rounding noise (the renderer measures in whole or half device pixels; 83 px / 2.5 is 33.2 in Double,
/// 33.2000008 in Float, and that noise decides which way a half-pixel centring tie snaps).
public enum TextLayoutPrecision {
    /// A device-pixel value from the renderer as DIP, divided in Double.
    public static func dip(px: Float, scale: Float) -> CGFloat { CGFloat(Double(px) / Double(scale)) }
    /// A Float DIP value that is a whole number of device pixels (the F1 table's heights and baselines, G21) as the exact Double DIP; any other value is only widened.
    public static func exactDIP(_ dip: Float, scale: Float) -> CGFloat {
        let s = Double(scale), d = Double(dip), px = (d * s).rounded()
        return CGFloat(abs(d * s - px) < 1e-3 ? px / s : d)
    }
}

/// The width a Text reports for an offered width. SwiftUI never reports more width than it was offered (macOS 27 measured, decision L1): a Text offered 0 reports 0, a
/// truncated single line reports at most the offer, and a line with no room for even its ellipsis reports the offer itself (the glyphs are clipped, not laid out wider).
/// The shaped run keeps its own (possibly wider) extent; only the reported frame is clamped, and `RetainedRunChoice` is given the same clamped width.
public enum TextReportedWidth {
    /// `widthPX` is the shaped extent; `proposedDIP` the width the stack offered (nil: unbounded); the result is in physical pixels.
    public static func clamp(_ widthPX: Float, proposedDIP: CGFloat?, scale: Float) -> Float {
        guard let proposedDIP, proposedDIP.isFinite else { return widthPX }
        return min(widthPX, Float(max(0, proposedDIP)) * scale)
    }
}

/// The retained-run choice: among measured requests of the same text and font, those whose measured physical extent can
/// have been snapped to the resolved bounds; all candidates must agree (else the run is ambiguous and refused).
enum RetainedRunChoice {
    struct Entry {
        let proposedWidth: CGFloat?
        let width: Float, height: Float, lines: Int, firstBaseline: Float
        /// The shaped run's own width when `width` is the (clamped) width reported to the layout; nil when they are the same.
        var shapedWidth: Float? = nil
    }
    static func choose(_ entries: [Entry], bounds: Rect, scale: Float, text: String) throws -> Entry {
        var candidates = entries.filter {
            snappedExtentCanMatch($0.width, bounds.w, origin: bounds.x, scale: scale)
                && snappedExtentCanMatch($0.height, bounds.h, origin: bounds.y, scale: scale)
        }.sorted { ($0.proposedWidth ?? .infinity) < ($1.proposedWidth ?? .infinity) }
        if candidates.isEmpty {
            // Half-pixel ties (round 5, hub gap R5; decision E12): a text whose origin or height lands on a half device pixel (a baseline-aligned row, an odd offset) has its
            // box snapped one pixel shorter than the run it measured. The run is painted at its measured size from the snapped origin, so a measurement within one pixel of the
            // bounds on each axis is the run; the closest one wins. Anything further off is still refused.
            candidates = entries.filter { abs($0.width - bounds.w) <= 1 && abs($0.height - bounds.h) <= 1 }
                .sorted { (abs($0.width - bounds.w) + abs($0.height - bounds.h), $0.proposedWidth ?? .infinity) < (abs($1.width - bounds.w) + abs($1.height - bounds.h), $1.proposedWidth ?? .infinity) }
            if let first = candidates.first { candidates = candidates.filter { abs($0.width - bounds.w) + abs($0.height - bounds.h) == abs(first.width - bounds.w) + abs(first.height - bounds.h) } }
        }
        guard let chosen = candidates.first else { throw HostPaintError.measuredRunGeometryMismatch(text) }
        // The run is what is painted: candidates that differ only in the width they REPORTED (the same shaped run offered 1.1 and 1.2 pt, both clamped to a frame of 3 px:
        // decision L1) are one run.
        guard candidates.allSatisfy({ ($0.shapedWidth ?? $0.width) == (chosen.shapedWidth ?? chosen.width) && $0.height == chosen.height && $0.lines == chosen.lines && $0.firstBaseline == chosen.firstBaseline }) else {
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
    public let systemFonts: SystemFontMapper
    public private(set) var failures: [String] = []
    /// Every distinct place the Windows font differs from the requested one (weight, design, width, family, renderer limits), in first-seen order. Also logged as `FONT_ADAPTED`.
    public var adaptedFonts: [FontAdaptation] { adaptationLog.entries }
    private var adaptationLog = FontAdaptationLog()
    private let log: (String) -> Void
    private var firstBaselines: [TextMeasureRequest: Float] = [:]
    private struct ColouredKey: Hashable { let request: TextMeasureRequest; let color: UInt32 }
    private var retained: [TextMeasureRequest: SwiftRightBridge.TextMeasurement] = [:]
    private var coloured: [ColouredKey: SwiftRightBridge.TextMeasurement] = [:]
    private static let cacheBound = 8192

    public init(bridge: Bridge, scale: Float, body: BodyFontProfile, fonts: CustomFontResolving? = nil,
                textColor: UInt32 = 0x272727ff, systemFonts: SystemFontMapper? = nil, log: @escaping (String) -> Void = { print($0) }) {
        self.bridge = bridge; self.scale = scale; self.body = body; self.fonts = fonts; self.textColor = textColor; self.log = log
        // A 0.8 renderer says which system families exist; a 0.7 renderer cannot, so Windows 11 is assumed (decision G42).
        if let systemFonts { self.systemFonts = systemFonts }
        else if bridge.supportsTextExtension, let info = try? bridge.systemFontInfo() {
            self.systemFonts = SystemFontMapper(availability: SystemFontAvailability(info))
            log("SYSTEM_FONTS segoeUIVariable=\(info.segoeUIVariable) cascadiaMono=\(info.cascadiaMono) sitka=\(info.sitka)")
        } else { self.systemFonts = SystemFontMapper() }
    }

    /// True when the renderer takes the F2 request extras (ABI 0.8: feature list, baseline offset, simulation policy).
    private var rendererHasExtendedRequest: Bool { bridge.supportsTextExtension }

    private func record(_ adaptations: [FontAdaptation]) {
        for a in adaptationLog.record(adaptations) { log(a.description) }
    }

    /// One renderer measurement of `r`: on a 0.8 renderer the request carries the extension (Mac baseline, kern=1, no synthesis, tnum); on a 0.7 renderer it is the 0.7
    /// request (family, weight, size, line height) and what the 0.7 request cannot carry is recorded as adapted, never dropped silently (decision G62).
    private func measureOnce(_ r: MeasureRequest, request: TextMeasureRequest) throws -> SwiftRightBridge.TextMeasurement {
        let plan = try TextRequestAdapter.systemPlan(for: request, scale: scale, systemFonts: systemFonts)
        var r = r
        if rendererHasExtendedRequest {
            if let plan { record(plan.adaptations) }
            r.extension = plan?.textExtension ?? TextRequestAdapter.customExtension
        } else {
            if let plan { record(plan.adaptations + SystemFontMapper.abi07Limits(of: plan)) }
            else { record(SystemFontMapper.abi07CustomLimits) }
            r.extension = nil
            // The Mac pitch needs the renderer to round the block (it does so only with a 0.8 baseline): a 0.7 renderer keeps the single-line height per line.
            if let plan { r.lineHeight = plan.lineHeightDIP }
        }
        // A styled-Text run (#68): italic, kerning and tracking ride in the 0.8 extension. A 0.7 renderer cannot carry them, so the run is drawn without and that is logged, not hidden.
        if let style = request.runStyle, !style.isDefault {
            if rendererHasExtendedRequest {
                var e = r.extension ?? TextExtension()
                if style.italic {
                    e.italic = true
                    e.simulations.remove(.forbidOblique)   // Segoe UI Variable has no italic face: DirectWrite slants the upright one
                }
                e.trackingDIP = Float(style.tracking)
                e.kerningDIP = Float(style.kern)
                r.extension = e
            } else {
                record([FontAdaptation(kind: .family, requested: "run style italic=\(style.italic) kern=\(style.kern) tracking=\(style.tracking)", applied: "none",
                                       reason: "the renderer predates ABI 0.8: no italic, kerning or tracking")])
            }
        }
        return try bridge.measure(r)
    }

    /// Shapes `request` in `color` (the single-line search for `lineLimit(1)` included); the caller owns the returned run.
    private func shape(_ request: TextMeasureRequest, color: UInt32) throws -> SwiftRightBridge.TextMeasurement {
        let shaping = try TextRequestAdapter.shapingRequest(for: request, body: body, fonts: fonts, scale: scale, textColor: color, systemFonts: systemFonts)
        if let limit = request.lineLimit {
            let viaRenderer = try NativeLineLimit.shape(shaping, limit: limit, rendererSupportsMaxLines: rendererHasExtendedRequest,
                native: { try measureOnce($0, request: request) },
                applied: { $0.extensionReport?.applied.contains(.maxLines) == true },
                release: { _ = bridge.release($0.run) },
                fallback: { try hostSideLineLimit(shaping, limit: limit, request: request) })
            if viaRenderer.native { log("TEXT_MAX_LINES native lineLimit=\(limit) originalUTF8=\(request.text.utf8.count) lines=\(viaRenderer.measurement.lineCount) maxWidthPX=\(shaping.maxWidth)") }
            return viaRenderer.measurement
        }
        return try measureOnce(shaping, request: request)
    }

    /// The pre-#51 path: the longest prefix plus an ellipsis found by measuring candidates (renderers without SWR_M08_MAX_LINES).
    private func hostSideLineLimit(_ shaping: MeasureRequest, limit: Int, request: TextMeasureRequest) throws -> SwiftRightBridge.TextMeasurement {
        do {
            let selection = try SingleLineText.select(request.text, maxWidth: shaping.maxWidth, lineLimit: limit,
                measure: { candidate -> SwiftRightBridge.TextMeasurement in
                    var r = shaping; r.text = candidate
                    return try measureOnce(r, request: request)
                },
                width: { $0.width }, lineCount: { $0.lineCount }, release: { _ = bridge.release($0.run) })
            log("TEXT_SINGLE_LINE originalUTF8=\(request.text.utf8.count) displayUTF8=\(selection.displayText.utf8.count) lineLimit=\(limit) candidateCount=\(selection.candidateCount) maxWidthPX=\(shaping.maxWidth)")
            return selection.measurement
        } catch TextMeasureError.noCandidateFits {
            // Not even the ellipsis fits the offered width (decision F2): the ellipsis alone, which overflows the offer by its own width. macOS clips the first glyphs instead.
            var r = shaping; r.text = "\u{2026}"
            log("TEXT_ELLIPSIS_ONLY originalUTF8=\(request.text.utf8.count) lineLimit=\(limit) maxWidthPX=\(shaping.maxWidth)")
            return try measureOnce(r, request: request)
        }
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
                let plan = try TextRequestAdapter.systemPlan(for: request, scale: scale, systemFonts: systemFonts)
                if let plan { firstBaselines[request] = plan.firstBaselineDIP }
                let shaping = try TextRequestAdapter.shapingRequest(for: request, body: body, fonts: fonts, scale: scale, textColor: textColor, systemFonts: systemFonts)
                let sentLineHeight = rendererHasExtendedRequest ? shaping.lineHeight : (plan?.lineHeightDIP ?? shaping.lineHeight)   // the value measureOnce sent
                log("TEXT_MEASURE text=\(request.text) fontID=\(request.fontID) family=\(shaping.fontFamily) weight=\(shaping.weight) fontSizeDIP=\(shaping.fontSize) lineHeightDIP=\(sentLineHeight) proposedDIP=\(request.proposedWidth.map(String.init(describing:)) ?? "nil") widthPX=\(result.width) heightPX=\(result.height) firstBaselinePX=\(result.firstBaseline) layoutBaselineDIP=\(firstBaselines[request].map { String(describing: $0) } ?? "renderer") lines=\(result.lineCount) lineLimit=\(request.lineLimit.map(String.init) ?? "nil") scale=\(scale)")
            }
            // A system font's frame and first baseline are the Mac's (F1 table, decision G70): the layout baseline is the table's, whichever renderer paints it.
            // Float to CGFloat only through `TextLayoutPrecision`: a Float quotient (33.2 as 33.2000008) moves a half-pixel centring tie and drives the layout by rounding noise.
            let baseline = firstBaselines[request].map { TextLayoutPrecision.exactDIP($0, scale: scale) } ?? TextLayoutPrecision.dip(px: result.firstBaseline, scale: scale)
            let reportedWidth = TextReportedWidth.clamp(result.width, proposedDIP: request.proposedWidth, scale: scale)
            return SwiftRightRuntime.TextMeasurement(size: LayoutSize(width: TextLayoutPrecision.dip(px: reportedWidth, scale: scale), height: TextLayoutPrecision.dip(px: result.height, scale: scale)),
                                                     baseline: baseline, lineCount: result.lineCount,
                                                     lastBaseline: result.lastBaseline.isFinite && result.lineCount > 0 ? baseline + TextLayoutPrecision.dip(px: result.lastBaseline - result.firstBaseline, scale: scale) : nil)
        } catch {
            failures.append("measure '\(request.text.prefix(40))' fontID=\(request.fontID): \(error)")
            return SwiftRightRuntime.TextMeasurement(size: .zero, baseline: 0, lineCount: 0)
        }
    }

    /// The retained measurement a Text node of these resolved pixel bounds paints: among the requests of the same text and font, the one whose reported (clamped, see
    /// `TextReportedWidth`) extent can have been snapped to the bounds.
    private func retainedMatch(text: String, font: Font?, style: TextRunStyle? = nil, bounds: Rect) throws -> (key: TextMeasureRequest, value: SwiftRightBridge.TextMeasurement, chosen: RetainedRunChoice.Entry) {
        let fontID = font?.id ?? "body"
        let metadata = font?.metadata
        func reported(_ key: TextMeasureRequest, _ value: SwiftRightBridge.TextMeasurement) -> Float {
            TextReportedWidth.clamp(value.width, proposedDIP: key.proposedWidth, scale: scale)
        }
        let matching = retained.filter { $0.key.text == text && $0.key.fontID == fontID && $0.key.fontMetadata == metadata && Float($0.key.scale) == scale && $0.key.runStyle == style }
        let entries = matching.map { RetainedRunChoice.Entry(proposedWidth: $0.key.proposedWidth, width: reported($0.key, $0.value), height: $0.value.height,
                                                             lines: $0.value.lines.count, firstBaseline: $0.value.firstBaseline, shapedWidth: $0.value.width) }
        let chosen = try RetainedRunChoice.choose(entries, bounds: bounds, scale: scale, text: text)
        guard let source = matching.first(where: { $0.key.proposedWidth == chosen.proposedWidth && reported($0.key, $0.value) == chosen.width && $0.value.height == chosen.height }) else {
            throw HostPaintError.measuredRunGeometryMismatch(text)
        }
        return (source.key, source.value, chosen)
    }

    /// The retained shaped run for a Text node of the given resolved pixel bounds.
    public func run(text: String, font: Font?, bounds: Rect) throws -> TextRunHandle {
        let (_, value, chosen) = try retainedMatch(text: text, font: font, bounds: bounds)
        log("TEXT_RETAINED_RUN text=\(text) widthPX=\(chosen.width) heightPX=\(chosen.height) snappedWidthPX=\(bounds.w) lines=\(chosen.lines) proposedDIP=\(chosen.proposedWidth.map(String.init(describing:)) ?? "nil")")
        return value.run
    }

    /// The retained run of `run(text:font:bounds:)` re-shaped in `color`: same text, font and width, so the same geometry. Retained per request and colour.
    public func run(text: String, font: Font?, bounds: Rect, color: UInt32) throws -> TextRunHandle {
        guard color != textColor else { return try run(text: text, font: font, bounds: bounds) }
        let (key, value, chosen) = try retainedMatch(text: text, font: font, bounds: bounds)
        let coloredKey = ColouredKey(request: key, color: color)
        if let hit = coloured[coloredKey] { return hit.run }
        guard coloured.count < Self.cacheBound else { throw TextMeasureError.measurementCacheBound }
        let result = try shape(key, color: color)
        guard result.width == value.width, result.height == chosen.height, result.lines.count == chosen.lines else {
            _ = bridge.release(result.run)
            throw HostPaintError.measuredRunGeometryMismatch(text)
        }
        coloured[coloredKey] = result
        log("TEXT_COLOURED_RUN text=\(text) colorRGBA=\(String(format: "%08x", color)) widthPX=\(result.width) heightPX=\(result.height)")
        return result.run
    }

    public func naturalRun(text: String, font: Font?, color: UInt32) throws -> NaturalTextRun? {
        let fontID = font?.id ?? "body"
        let metadata = font?.metadata
        guard let source = retained.first(where: { $0.key.text == text && $0.key.fontID == fontID && $0.key.fontMetadata == metadata
                                                    && Float($0.key.scale) == scale && $0.key.proposedWidth == nil && $0.key.lineLimit == nil && $0.key.runStyle == nil }) else { return nil }
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

    /// `run(text:font:bounds:color:)` for a styled-Text run (#68): the retained measurement of the same text, font and style whose extent can be the bounds, in `color`.
    public func run(text: String, font: Font?, style: TextRunStyle?, bounds: Rect, color: UInt32?) throws -> TextRunHandle {
        guard style != nil else {
            if let color { return try run(text: text, font: font, bounds: bounds, color: color) }
            return try run(text: text, font: font, bounds: bounds)
        }
        let (key, value, chosen) = try retainedMatch(text: text, font: font, style: style, bounds: bounds)
        guard let color, color != textColor else { return value.run }
        let coloredKey = ColouredKey(request: key, color: color)
        if let hit = coloured[coloredKey] { return hit.run }
        guard coloured.count < Self.cacheBound else { throw TextMeasureError.measurementCacheBound }
        let result = try shape(key, color: color)
        guard result.width == value.width, result.height == chosen.height, result.lines.count == chosen.lines else {
            _ = bridge.release(result.run)
            throw HostPaintError.measuredRunGeometryMismatch(text)
        }
        coloured[coloredKey] = result
        return result.run
    }

    public func runOverflows(text: String, font: Font?, style: TextRunStyle?, bounds: Rect) -> Bool {
        guard let match = try? retainedMatch(text: text, font: font, style: style, bounds: bounds) else { return false }
        return match.value.width > bounds.w + 1
    }

    /// One fragment of a styled Text at its natural size: the retained unwrapped measurement of exactly this text, font and style (measured now when the layout never asked for it,
    /// as a merged stretch of words is not one of the words it measured), in `color` (nil: the measurer's own colour).
    public func fragmentRun(text: String, font: Font?, style: TextRunStyle?, color: UInt32?) throws -> NaturalTextRun? {
        let fontID = font?.id ?? "body"
        let metadata = font?.metadata
        func find() -> (key: TextMeasureRequest, value: SwiftRightBridge.TextMeasurement)? {
            retained.first(where: { $0.key.text == text && $0.key.fontID == fontID && $0.key.fontMetadata == metadata && Float($0.key.scale) == scale
                                     && $0.key.proposedWidth == nil && $0.key.lineLimit == nil && $0.key.runStyle == style }).map { ($0.key, $0.value) }
        }
        if find() == nil {
            _ = measure(TextMeasureRequest(text: text, fontID: fontID, proposedWidth: nil, scale: CGFloat(scale), fontMetadata: metadata, lineLimit: nil, runStyle: style))
        }
        guard let source = find() else { return nil }
        let measured = source.value
        guard let color, color != textColor else {
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

    public func runOverflows(text: String, font: Font?, bounds: Rect) -> Bool {
        guard let match = try? retainedMatch(text: text, font: font, bounds: bounds) else { return false }
        return match.value.width > bounds.w + 1   // more than a pixel of rounding
    }

    public func releaseAll() {
        retained.values.forEach { _ = bridge.release($0.run) }
        retained.removeAll()
        firstBaselines.removeAll()
        coloured.values.forEach { _ = bridge.release($0.run) }
        coloured.removeAll()
    }
}
