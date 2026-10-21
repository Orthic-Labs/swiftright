import Foundation
import SwiftRightRuntime
import SwiftRightBridge

// Block F2 (docs/foundations-images-fonts.md section 2.1, decisions G40-G44 and G70+): SwiftUI system fonts (`Font.system`, the eleven text styles, designs, weights,
// width, `monospacedDigit`) on Windows. Mac vertical metrics (the F1 table, `FontMetricTable.shared`), Windows glyphs (Segoe UI Variable, Cascadia Mono, Sitka).
// Everything in this file is pure: no renderer, no Windows API, so every rule is unit-testable on the Mac.

/// One place where the Windows rendering differs from the requested SwiftUI font, reported (host log line and `BridgeTextMeasurer.adaptedFonts`), never silent.
public struct FontAdaptation: Hashable, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable { case weight, design, width, feature, family, baseline }
    public let kind: Kind
    public let requested: String
    public let applied: String
    public let reason: String
    public init(kind: Kind, requested: String, applied: String, reason: String) {
        self.kind = kind; self.requested = requested; self.applied = applied; self.reason = reason
    }
    /// The visible host log line.
    public var description: String { "FONT_ADAPTED kind=\(kind.rawValue) requested=\(requested) applied=\(applied) reason=\(reason)" }
}

/// First-seen-ordered set of adaptations: `record` returns the ones not seen before (the caller logs those once).
public struct FontAdaptationLog: Equatable, Sendable {
    public private(set) var entries: [FontAdaptation] = []
    private var seen = Set<FontAdaptation>()
    public init() {}
    @discardableResult public mutating func record(_ adaptations: [FontAdaptation]) -> [FontAdaptation] {
        var fresh: [FontAdaptation] = []
        for a in adaptations where seen.insert(a).inserted { entries.append(a); fresh.append(a) }
        return fresh
    }
}

/// Which system families the machine has (ABI 0.8 `swr_system_font_info`; a 0.7 renderer cannot tell, so Windows 11 is assumed, decision G42).
public struct SystemFontAvailability: Equatable, Sendable {
    public var segoeUIVariable: Bool, cascadiaMono: Bool, sitka: Bool
    public init(segoeUIVariable: Bool = true, cascadiaMono: Bool = true, sitka: Bool = true) {
        self.segoeUIVariable = segoeUIVariable; self.cascadiaMono = cascadiaMono; self.sitka = sitka
    }
    public static let windows11 = SystemFontAvailability()
    /// What an ABI 0.8 renderer reports (`Bridge.systemFontInfo()`).
    public init(_ info: SystemFontInfo) { self.init(segoeUIVariable: info.segoeUIVariable, cascadiaMono: info.cascadiaMono, sitka: info.sitka) }
}

/// A system font resolved for the renderer: the Windows face to ask for, and the Mac line geometry to lay it out with.
public struct SystemFontPlan: Equatable {
    public var family: String
    /// The weight of a face that exists in `family` (never a weight the renderer would have to snap or synthesise).
    public var weight: UInt32
    public var sizeDIP: Float
    /// Mac one-line height in DIP at the request's scale (F1 table).
    public var lineHeightDIP: Float
    /// Mac line pitch in DIP (decision G75b): the table's scale-1 line height, which SwiftUI stacks lines by at every scale and rounds once per block
    /// (round(n x pitch x scale) px). Equals `lineHeightDIP` unless the scale-1 height times the scale does not round (half-up) to the measured
    /// single-line height, in which case the pitch is not derivable from the table and the old per-line stacking stays.
    public var linePitchDIP: Float
    /// Mac first baseline from the line top in DIP at the request's scale (F1 table).
    public var firstBaselineDIP: Float
    public var features: [OpenTypeFeature]
    public var simulations: SimulationPolicy
    public var fallbackFamilies: [String]
    public var adaptations: [FontAdaptation]
    /// Text style name, nil for `Font.system(size:)`.
    public var textStyle: String?

    /// The ABI 0.8 request extension of this plan: the Mac first baseline, kern=1 (and tnum), no synthesis, the system fallback families (G61).
    public var textExtension: TextExtension {
        TextExtension(features: features, simulations: simulations, fallbackFamilies: fallbackFamilies, baselineOffsetDIP: firstBaselineDIP)
    }
}

/// The Segoe UI Variable optical family chosen by size (decision G70).
public enum SegoeOpticalFamily: String, Sendable {
    case small = "Segoe UI Variable Small", text = "Segoe UI Variable Text", display = "Segoe UI Variable Display"

    /// The three families are named instances of one variable file with opsz 8 (Small), 10.5 (Text) and 36 (Display) (F0, G11); gpui does no automatic optical sizing, so the
    /// host picks the family whose opsz is nearest, by log distance, to the run's optical size. A DIP is 0.75 pt. Boundaries: sqrt(8 x 10.5) / 0.75 = 12.2 DIP and
    /// sqrt(10.5 x 36) / 0.75 = 25.9 DIP (so 12 DIP is Small, 12.5 DIP is Text, 25.5 DIP is Text, 26 DIP is Display).
    public static let smallTextBoundaryDIP: Float = Float((8.0 * 10.5).squareRoot() / 0.75)
    public static let textDisplayBoundaryDIP: Float = Float((10.5 * 36.0).squareRoot() / 0.75)

    public static func family(forSizeDIP size: Float) -> SegoeOpticalFamily {
        if size < smallTextBoundaryDIP { return .small }
        if size < textDisplayBoundaryDIP { return .text }
        return .display
    }
}

/// The SwiftUI text styles of macOS: size, default weight and emphasized (`.bold()`) weight (G23, G24, G25).
public enum MacTextStyles {
    public struct Entry: Equatable, Sendable { public let size: Float; public let weight: Font.Weight; public let emphasized: Font.Weight }
    public static let all: [String: Entry] = [
        "largeTitle": Entry(size: 26, weight: .regular, emphasized: .bold),
        "title": Entry(size: 22, weight: .regular, emphasized: .bold),
        "title2": Entry(size: 17, weight: .regular, emphasized: .bold),
        "title3": Entry(size: 15, weight: .regular, emphasized: .semibold),
        "headline": Entry(size: 13, weight: .bold, emphasized: .heavy),
        "subheadline": Entry(size: 11, weight: .regular, emphasized: .semibold),
        "body": Entry(size: 13, weight: .regular, emphasized: .semibold),
        "callout": Entry(size: 12, weight: .regular, emphasized: .semibold),
        "footnote": Entry(size: 10, weight: .regular, emphasized: .semibold),
        "caption": Entry(size: 10, weight: .regular, emphasized: .medium),
        "caption2": Entry(size: 10, weight: .medium, emphasized: .semibold),
    ]
    public static let names = ["largeTitle", "title", "title2", "title3", "headline", "body", "callout", "subheadline", "footnote", "caption", "caption2"]
}

/// How a SwiftUI weight (ultraLight ... black) becomes a face that exists in a Windows family.
enum WeightMapping {
    struct Result { let weight: UInt32; let family: String?; let adapted: Bool; let note: String }

    /// Segoe UI Variable: named instances Light 300, Semilight 350, Regular 400, Semibold 600, Bold 700 (G11; wght is 300..700 on this build). Heavy and black have no Variable
    /// instance: static `Segoe UI` Black (900).
    static func segoeVariable(_ w: Font.Weight) -> Result {
        switch w {
        case .ultraLight: return Result(weight: 300, family: nil, adapted: true, note: "Segoe UI Variable has no 100 (wght starts at 300): Light")
        case .thin: return Result(weight: 300, family: nil, adapted: true, note: "Segoe UI Variable has no 200 (wght starts at 300): Light")
        case .light: return Result(weight: 300, family: nil, adapted: false, note: "")
        case .regular: return Result(weight: 400, family: nil, adapted: false, note: "")
        case .medium: return Result(weight: 600, family: nil, adapted: true, note: "no 500 instance (gpui snaps to named instances): Semibold")
        case .semibold: return Result(weight: 600, family: nil, adapted: false, note: "")
        case .bold: return Result(weight: 700, family: nil, adapted: false, note: "")
        case .heavy: return Result(weight: 900, family: "Segoe UI", adapted: true, note: "no 800 instance: static Segoe UI Black (900)")
        case .black: return Result(weight: 900, family: "Segoe UI", adapted: true, note: "no Variable 900: static Segoe UI Black")
        }
    }

    /// Static Segoe UI (no Segoe UI Variable): Light 300, Semilight 350, Regular, Semibold 600, Bold 700, Black 900.
    static func segoeStatic(_ w: Font.Weight) -> Result {
        switch w {
        case .ultraLight, .thin: return Result(weight: 300, family: nil, adapted: true, note: "static Segoe UI starts at Light (300)")
        case .light: return Result(weight: 300, family: nil, adapted: false, note: "")
        case .regular: return Result(weight: 400, family: nil, adapted: false, note: "")
        case .medium: return Result(weight: 600, family: nil, adapted: true, note: "static Segoe UI has no Medium: Semibold")
        case .semibold: return Result(weight: 600, family: nil, adapted: false, note: "")
        case .bold: return Result(weight: 700, family: nil, adapted: false, note: "")
        case .heavy: return Result(weight: 900, family: nil, adapted: true, note: "static Segoe UI has no 800: Black (900)")
        case .black: return Result(weight: 900, family: nil, adapted: false, note: "")
        }
    }

    /// Cascadia Mono: ExtraLight 200, Light 300, SemiLight 350, Regular 400, SemiBold 600, Bold 700.
    static func cascadia(_ w: Font.Weight) -> Result {
        switch w {
        case .ultraLight: return Result(weight: 200, family: nil, adapted: true, note: "Cascadia Mono starts at ExtraLight (200)")
        case .thin: return Result(weight: 200, family: nil, adapted: false, note: "")
        case .light: return Result(weight: 300, family: nil, adapted: false, note: "")
        case .regular: return Result(weight: 400, family: nil, adapted: false, note: "")
        case .medium: return Result(weight: 600, family: nil, adapted: true, note: "Cascadia Mono has no Medium: SemiBold")
        case .semibold: return Result(weight: 600, family: nil, adapted: false, note: "")
        case .bold: return Result(weight: 700, family: nil, adapted: false, note: "")
        case .heavy, .black: return Result(weight: 700, family: nil, adapted: true, note: "Cascadia Mono ends at Bold (700)")
        }
    }

    /// Consolas (the monospaced fallback): Regular and Bold only.
    static func consolas(_ w: Font.Weight) -> Result {
        switch w {
        case .regular: return Result(weight: 400, family: nil, adapted: false, note: "")
        case .bold: return Result(weight: 700, family: nil, adapted: false, note: "")
        case .semibold, .heavy, .black: return Result(weight: 700, family: nil, adapted: true, note: "Consolas has Regular and Bold only: Bold")
        case .ultraLight, .thin, .light, .medium: return Result(weight: 400, family: nil, adapted: true, note: "Consolas has Regular and Bold only: Regular")
        }
    }

    /// Sitka Text and its fallback Georgia: Regular and Bold.
    static func twoFace(_ w: Font.Weight, name: String) -> Result {
        switch w {
        case .regular: return Result(weight: 400, family: nil, adapted: false, note: "")
        case .bold: return Result(weight: 700, family: nil, adapted: false, note: "")
        case .semibold, .heavy, .black: return Result(weight: 700, family: nil, adapted: true, note: "\(name) has Regular and Bold only: Bold")
        case .ultraLight, .thin, .light, .medium: return Result(weight: 400, family: nil, adapted: true, note: "\(name) has Regular and Bold only: Regular")
        }
    }
}

/// System fonts: SwiftUI font to Windows face plus Mac geometry. Pure.
public struct SystemFontMapper: Sendable {
    public var availability: SystemFontAvailability
    public init(availability: SystemFontAvailability = .windows11) { self.availability = availability }

    public static let sitkaFamily = "Sitka Text"
    public static let cascadiaFamily = "Cascadia Mono"
    public static let monospacedFallback = "Consolas"
    public static let serifFallback = "Georgia"
    public static let staticSegoe = "Segoe UI"

    /// The scales the F1 table was measured at (G21; 1.25 and 1.5 added for #70). Any other scale fails visibly until measured.
    public static let measuredScales: [Double] = [1, 1.25, 1.5, 2.5]
    public static func metricScale(_ scale: Float) throws -> Double {
        if let s = measuredScales.first(where: { abs(Float($0) - scale) < 1e-4 }) { return s }
        throw TextMeasureError.unsupportedScale(scale)
    }

    /// The plan of a system font (`metadata.isCustom == false`, or the body font when `metadata` is nil).
    public func plan(for metadata: Font.Metadata?, scale: Float, table: FontMetricTable = .shared) throws -> SystemFontPlan {
        let s = try Self.metricScale(scale)
        guard table.isLoaded else { throw TextMeasureError.systemFontMetricsUnavailable("font metric table not loaded") }
        let md = metadata ?? Font.Metadata(textStyle: "body")
        let design = md.design ?? .default
        var adaptations: [FontAdaptation] = []

        // size, weight and the Mac line from the table
        let sizeDIP: Float, requestedWeight: Font.Weight, line: FontMetricTable.Line, line1: FontMetricTable.Line?, styleName: String?
        if let style = md.textStyle {
            guard let entry = MacTextStyles.all[style] else { throw TextMeasureError.unsupportedFont("textStyle.\(style)") }
            sizeDIP = entry.size
            requestedWeight = md.weight ?? (md.isEmphasized ? entry.emphasized : entry.weight)
            let variant = design == .default ? "default" : "design-\(design.rawValue)"
            guard let l = table.style(style, variant: variant, scale: s) else { throw TextMeasureError.systemFontMetricsUnavailable("textStyle \(style) \(variant) scale \(s)") }
            line = l; styleName = style
            line1 = table.style(style, variant: variant, scale: 1)
        } else {
            guard let point = md.pointSize.map(Float.init), point.isFinite, point > 0, point <= 512 else { throw TextMeasureError.invalidPointSize }
            sizeDIP = point
            requestedWeight = md.weight ?? .regular
            guard let l = table.system(size: Double(point), weight: "regular", design: design.rawValue, scale: s) else {
                throw TextMeasureError.systemFontMetricsUnavailable("system size \(point) design \(design.rawValue) scale \(s) (measured: 9 to 40 pt in half points)")
            }
            line = l; styleName = nil
            line1 = table.system(size: Double(point), weight: "regular", design: design.rawValue, scale: 1)
        }

        // the Windows face
        var family: String, mapping: WeightMapping.Result, fallbacks: [String]
        switch design {
        case .default, .rounded:
            if availability.segoeUIVariable {
                family = SegoeOpticalFamily.family(forSizeDIP: sizeDIP).rawValue
                mapping = WeightMapping.segoeVariable(requestedWeight)
                fallbacks = [Self.staticSegoe]
            } else {
                family = Self.staticSegoe
                mapping = WeightMapping.segoeStatic(requestedWeight)
                fallbacks = []
                adaptations.append(FontAdaptation(kind: .family, requested: "system", applied: Self.staticSegoe,
                                                  reason: "Segoe UI Variable is not installed: static Segoe UI"))
            }
            if design == .rounded {
                adaptations.append(FontAdaptation(kind: .design, requested: "rounded", applied: "default (\(family))",
                                                  reason: "Windows has no rounded system face (design 2.1, G70)"))
            }
        case .monospaced:
            if availability.cascadiaMono {
                family = Self.cascadiaFamily; mapping = WeightMapping.cascadia(requestedWeight); fallbacks = [Self.monospacedFallback]
            } else {
                family = Self.monospacedFallback; mapping = WeightMapping.consolas(requestedWeight); fallbacks = []
                adaptations.append(FontAdaptation(kind: .family, requested: "monospaced", applied: Self.monospacedFallback, reason: "Cascadia Mono is not installed"))
            }
        case .serif:
            if availability.sitka {
                family = Self.sitkaFamily; mapping = WeightMapping.twoFace(requestedWeight, name: Self.sitkaFamily); fallbacks = [Self.serifFallback]
            } else {
                family = Self.serifFallback; mapping = WeightMapping.twoFace(requestedWeight, name: Self.serifFallback); fallbacks = []
                adaptations.append(FontAdaptation(kind: .family, requested: "serif", applied: Self.serifFallback, reason: "Sitka is not installed"))
            }
        }
        if let f = mapping.family { family = f }
        if mapping.adapted {
            adaptations.append(FontAdaptation(kind: .weight, requested: "\(requestedWeight.rawValue)(\(requestedWeight.classValue)) design=\(design.rawValue)",
                                              applied: "\(family) \(mapping.weight)", reason: mapping.note))
        }
        if let w = md.width, w.name != "standard" {
            adaptations.append(FontAdaptation(kind: .width, requested: w.name, applied: "standard", reason: "no width axis in the Windows system faces (G41)"))
        }

        var features: [OpenTypeFeature] = [.kern]
        if md.monospacedDigit { features.append(.tabularNumbers) }

        // device-pixel exact DIP values: the table's heights and baselines are multiples of 1/scale (G21)
        func dip(_ v: Double) -> Float { let px = (v * s).rounded(); return abs(v * s - px) < 1e-6 ? Float(px / s) : Float(v) }
        // the Mac multi-line pitch (G75b): the scale-1 height, valid only when it reproduces the measured single line at this scale (half-up px)
        var pitch = dip(line.height)
        if let h1 = line1?.height, ((h1 * s) + 0.5).rounded(.down) == (line.height * s).rounded() { pitch = Float(h1) }
        return SystemFontPlan(family: family, weight: mapping.weight, sizeDIP: sizeDIP, lineHeightDIP: dip(line.height), linePitchDIP: pitch, firstBaselineDIP: dip(line.firstBaseline),
                              features: features, simulations: .forbidAll, fallbackFamilies: fallbacks, adaptations: adaptations, textStyle: styleName)
    }

    /// Adaptations that exist only because the renderer is ABI 0.7: no feature list (kern=1 cannot be sent, `tnum` cannot be sent) and no baseline offset.
    public static func abi07Limits(of plan: SystemFontPlan) -> [FontAdaptation] {
        var out = [FontAdaptation(kind: .feature, requested: "kern=1", applied: "off", reason: "the 0.7 request has no feature list; kerning needs ABI 0.8 (F3)"),
                   FontAdaptation(kind: .baseline, requested: "first baseline from the Mac table", applied: "round(hhea ascent) of the Windows face",
                                  reason: "baseline_offset_dip needs ABI 0.8 (F3); layout still uses the table baseline")]
        if plan.features.contains(.tabularNumbers) {
            out.append(FontAdaptation(kind: .feature, requested: "monospacedDigit (tnum=1)", applied: "proportional digits", reason: "the 0.7 request has no feature list; needs ABI 0.8 (F3)"))
        }
        return out
    }

    /// The same for a bundled (custom) font: kerning cannot be turned on through a 0.7 request.
    public static let abi07CustomLimits = [FontAdaptation(kind: .feature, requested: "kern=1", applied: "off", reason: "the 0.7 request has no feature list; kerning needs ABI 0.8 (F3)")]
}
