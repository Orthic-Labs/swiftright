import CSwiftRight
import Foundation

// Text extension (ABI rev 0.8, minimal form; swiftright.h "REVISION 0.8"; decisions G60-G69).
//
// A 0.8 renderer adds swr_measure_text_v08, swr_text_run_faces, swr_font_face_metrics and
// swr_system_font_info. This file is the platform-neutral Swift side: request/report types, marshalling,
// and accessors, all unit-tested on the Mac through fake entry points.
//
// Policy (never silent): `MeasureRequest.extension == nil` ALWAYS takes the 0.6 measure path and behaves
// exactly as before on every renderer. A request that carries an extension on a renderer without the 0.8
// entries THROWS SWR_E_UNSUPPORTED instead of dropping tracking, features or the baseline offset: the host
// checks `Bridge.supportsTextExtension` and decides (send `nil` and report the loss, or refuse).

public typealias MeasureV08Fn = @convention(c) (UnsafePointer<swr_measure_request_v08>?, UnsafeMutablePointer<swr_measure_result_v08>?) -> Int32
public typealias RunFacesFn = @convention(c) (UInt64, UnsafeMutablePointer<swr_run_face>?, UInt32, UnsafeMutablePointer<UInt32>?) -> Int32
public typealias FaceMetricsFn = @convention(c) (UnsafePointer<UInt8>?, UInt32, UInt32, UInt32, UInt32, UnsafeMutablePointer<swr_face_metrics>?) -> Int32
public typealias SystemFontInfoFn = @convention(c) (UnsafeMutablePointer<swr_system_fonts>?) -> Int32

/// The four 0.8 entry points of a renderer's table.
public struct TextExtensionEntryPoints {
    public let measure: MeasureV08Fn
    public let runFaces: RunFacesFn
    public let faceMetrics: FaceMetricsFn
    public let systemFontInfo: SystemFontInfoFn
    public init(measure: @escaping MeasureV08Fn, runFaces: @escaping RunFacesFn,
                faceMetrics: @escaping FaceMetricsFn, systemFontInfo: @escaping SystemFontInfoFn) {
        self.measure = measure; self.runFaces = runFaces; self.faceMetrics = faceMetrics; self.systemFontInfo = systemFontInfo
    }
}

/// One OpenType feature (tag, value). `OpenTypeFeature("kern")` is kern=1. The host sends kern=1 on every
/// Windows run: gpui/DirectWrite leave kerning off by default (G15), the Mac kerns by default.
public struct OpenTypeFeature: Equatable {
    public var tag: UInt32
    public var value: UInt32
    public init(tag: UInt32, value: UInt32 = 1) { self.tag = tag; self.value = value }
    /// A four-character tag ("kern", "tnum", "pnum"). Precondition: exactly four ASCII bytes.
    public init(_ tag: String, _ value: UInt32 = 1) {
        let b = Array(tag.utf8)
        precondition(b.count == 4 && b.allSatisfy { $0 >= 0x20 && $0 < 0x7F }, "OpenType tag must be four printable ASCII characters")
        self.tag = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        self.value = value
    }
    public static let kern = OpenTypeFeature("kern")
    public static let tabularNumbers = OpenTypeFeature("tnum")
    public var tagString: String {
        String(decoding: [UInt8(tag >> 24 & 0xFF), UInt8(tag >> 16 & 0xFF), UInt8(tag >> 8 & 0xFF), UInt8(tag & 0xFF)], as: UTF8.self)
    }
}

/// Which DirectWrite simulations the renderer may use. A forbidden one draws the nearest REAL face (the
/// Mac does not synthesise, G27) and is reported.
public struct SimulationPolicy: OptionSet, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let forbidBold = SimulationPolicy(rawValue: UInt32(SWR_SIM_FORBID_BOLD))
    public static let forbidOblique = SimulationPolicy(rawValue: UInt32(SWR_SIM_FORBID_OBLIQUE))
    public static let forbidAll: SimulationPolicy = [.forbidBold, .forbidOblique]
}

/// The 0.8 additions to a measure request. Every default keeps the 0.6 behaviour, so only the fields a host
/// sets differ.
public struct TextExtension: Equatable {
    /// wght; nil = `MeasureRequest.weight`. Snaps to the nearest named instance (ties heavier, 500 -> 600).
    public var weight: Float? = nil
    public var italic: Bool = false
    /// wdth percent. IGNORED by the renderer unless 0 or 100 (reported): gpui cannot select a width axis.
    public var width: Float = 0
    /// opsz. IGNORED unless 0 (reported): name the family (Segoe UI Variable Text, Display or Small) instead.
    public var opticalSize: Float = 0
    /// slant degrees. IGNORED unless 0 (reported).
    public var slant: Float = 0
    /// Added after every glyph cluster (DIP).
    public var trackingDIP: Float = 0
    /// Additive like tracking (DIP). Pair kerning is the `kern` feature.
    public var kerningDIP: Float = 0
    /// At most 16.
    public var features: [OpenTypeFeature] = []
    public var simulations: SimulationPolicy = []
    /// System families only, at most 8, highest priority first. A bundled family is reported as ignored (F3b).
    public var fallbackFamilies: [String] = []
    /// Puts the face's baseline this far (DIP) below the top of the line box. nil = the renderer's default
    /// placement (round(hhea ascent) for a bundled face, gpui's ascent otherwise).
    public var baselineOffsetDIP: Float? = nil

    public init(weight: Float? = nil, italic: Bool = false, width: Float = 0, opticalSize: Float = 0, slant: Float = 0,
                trackingDIP: Float = 0, kerningDIP: Float = 0, features: [OpenTypeFeature] = [],
                simulations: SimulationPolicy = [], fallbackFamilies: [String] = [], baselineOffsetDIP: Float? = nil) {
        self.weight = weight; self.italic = italic; self.width = width; self.opticalSize = opticalSize; self.slant = slant
        self.trackingDIP = trackingDIP; self.kerningDIP = kerningDIP; self.features = features
        self.simulations = simulations; self.fallbackFamilies = fallbackFamilies; self.baselineOffsetDIP = baselineOffsetDIP
    }

    public static let featuresMax = Int(SWR_FEATURES_MAX)
    public static let fallbacksMax = Int(SWR_FALLBACKS_MAX)
}

public struct TextExtensionApplied: OptionSet, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let features = TextExtensionApplied(rawValue: UInt32(SWR_M08_APPLIED_FEATURES))
    public static let tracking = TextExtensionApplied(rawValue: UInt32(SWR_M08_APPLIED_TRACKING))
    public static let baseline = TextExtensionApplied(rawValue: UInt32(SWR_M08_APPLIED_BASELINE))
    public static let fallbacks = TextExtensionApplied(rawValue: UInt32(SWR_M08_APPLIED_FALLBACKS))
    public static let weight = TextExtensionApplied(rawValue: UInt32(SWR_M08_APPLIED_WEIGHT))
    public static let italic = TextExtensionApplied(rawValue: UInt32(SWR_M08_APPLIED_ITALIC))
}

/// Requested and NOT done. A host that cares (the gates do) records these as adapted entries.
public struct TextExtensionIgnored: OptionSet, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let weightSnapped = TextExtensionIgnored(rawValue: UInt32(SWR_M08_IGN_WEIGHT_SNAPPED))
    public static let widthAxis = TextExtensionIgnored(rawValue: UInt32(SWR_M08_IGN_WIDTH_AXIS))
    public static let opticalSize = TextExtensionIgnored(rawValue: UInt32(SWR_M08_IGN_OPSZ))
    public static let slant = TextExtensionIgnored(rawValue: UInt32(SWR_M08_IGN_SLANT))
    public static let fallbackPrivate = TextExtensionIgnored(rawValue: UInt32(SWR_M08_IGN_FALLBACK_PRIVATE))
    public static let boldSimulationDropped = TextExtensionIgnored(rawValue: UInt32(SWR_M08_IGN_SIM_BOLD_DROPPED))
    public static let obliqueSimulationDropped = TextExtensionIgnored(rawValue: UInt32(SWR_M08_IGN_SIM_OBLIQUE_DROPPED))
}

public struct SimulationFlags: OptionSet, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let bold = SimulationFlags(rawValue: UInt32(SWR_SIMFLAG_BOLD))
    public static let oblique = SimulationFlags(rawValue: UInt32(SWR_SIMFLAG_OBLIQUE))
}

public struct TextExtensionReport: Equatable {
    public var applied: TextExtensionApplied
    public var ignored: TextExtensionIgnored
    /// The named instance drawn; 0 when the family is unknown to the renderer.
    public var resolvedWeight: Float
    public var resolvedItalic: Bool
    /// Simulation the shaper applies to this run.
    public var simulations: SimulationFlags
}

public struct RunFaceFlags: OptionSet, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let primary = RunFaceFlags(rawValue: UInt32(SWR_RUNFACE_PRIMARY))
    public static let bundled = RunFaceFlags(rawValue: UInt32(SWR_RUNFACE_BUNDLED))
    public static let system = RunFaceFlags(rawValue: UInt32(SWR_RUNFACE_SYSTEM))
    public static let fallback = RunFaceFlags(rawValue: UInt32(SWR_RUNFACE_FALLBACK))
    public static let unresolved = RunFaceFlags(rawValue: UInt32(SWR_RUNFACE_UNRESOLVED))
    public static let color = RunFaceFlags(rawValue: UInt32(SWR_RUNFACE_COLOR))
    public static let simulatedBold = RunFaceFlags(rawValue: UInt32(SWR_RUNFACE_SIM_BOLD))
    public static let simulatedOblique = RunFaceFlags(rawValue: UInt32(SWR_RUNFACE_SIM_OBLIQUE))
}

/// One shaped sub-run of a retained run (`Bridge.runFaces(of:)`).
public struct RunFace: Equatable {
    public var utf8Start: UInt32, utf8Len: UInt32
    public var glyphCount: UInt32
    /// Glyphs with id 0 (.notdef). The fallback gate requires 0.
    public var notdefCount: UInt32
    public var flags: RunFaceFlags
    public var weight: UInt32
    public var ascent: Float, descent: Float, advance: Float   // physical px
    /// Bundled primary face: SHA-256 of the registered bytes (the face hash the gate compares), else all zeros.
    public var sha256: [UInt8]
    public var family: String
    public var postScriptName: String
    public var version: String
    public var fileName: String
    public var sha256Hex: String { sha256.map { String(format: "%02x", $0) }.joined() }
    public var hasBundledHash: Bool { flags.contains(.bundled) }
}

public struct AxisRange: Equatable {
    public var tag: String
    public var minValue: Float, maxValue: Float, defaultValue: Float
}

public struct FaceMetrics: Equatable {
    public var found: Bool
    public var variable: Bool
    public var bundled: Bool
    public var source: FontSource
    public var weight: UInt32
    public var style: UInt32          // SWR_STYLE_*
    public var simulations: SimulationFlags
    public var unitsPerEm: Int32
    public var hheaAscent: Int32, hheaDescent: Int32, hheaLineGap: Int32
    public var typoAscent: Int32, typoDescent: Int32, typoLineGap: Int32
    public var winAscent: Int32, winDescent: Int32
    public var capHeight: Int32, xHeight: Int32
    public var axes: [AxisRange]
    public var sha256: [UInt8]
    public var family: String
    public var postScriptName: String
    public var version: String
    public var fileName: String

    /// CoreText-style ascent for the face at `pointSize` (hhea), the number the F1 table is built on.
    public func hheaAscent(pointSize: Float) -> Float { unitsPerEm > 0 ? pointSize * Float(hheaAscent) / Float(unitsPerEm) : 0 }
    public func hheaDescent(pointSize: Float) -> Float { unitsPerEm > 0 ? pointSize * abs(Float(hheaDescent)) / Float(unitsPerEm) : 0 }
}

public struct SystemFontEntry: Equatable {
    public var name: String
    public var version: String
    public var present: Bool
    public var faceCount: UInt32
}

public struct SystemFontInfo: Equatable {
    public var segoeUI: Bool
    /// Text, Display and Small all present.
    public var segoeUIVariable: Bool
    public var cascadiaMono: Bool
    public var sitka: Bool
    public var segoeUIEmoji: Bool
    public var segoeFluentIcons: Bool
    public var familyCount: UInt32
    public var entries: [SystemFontEntry]
}

// MARK: fixed C strings

func cString<T>(_ field: inout T) -> String {
    withUnsafeBytes(of: &field) { raw in String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self) }
}

func setCString<T>(_ field: inout T, _ s: String) {
    withUnsafeMutableBytes(of: &field) { raw in
        let b = Array(s.utf8.prefix(raw.count - 1))
        for i in 0..<raw.count { raw[i] = i < b.count ? b[i] : 0 }
    }
}

// MARK: Bridge

public extension Bridge {
    /// True when the renderer is ABI 0.8: `MeasureRequest.extension`, `runFaces`, `faceMetrics` and
    /// `systemFontInfo` work. False on a 0.6 or 0.7 renderer (they throw SWR_E_UNSUPPORTED, never degrade silently).
    var supportsTextExtension: Bool { textExtension != nil }

    private func unsupported(_ what: String) -> BridgeError {
        BridgeError.status(-15, "\(what) (renderer ABI \(revision) has no text extension)")
    }

    /// Builds the 0.8 request. Limits are checked here exactly as the renderer checks them, so a refusal is the same status
    /// on both sides.
    internal func withV08Request<R>(_ r: MeasureRequest, ext: TextExtension, lines: UnsafeMutablePointer<swr_line_info>, cap: Int, arena: Arena,
                                    _ body: (UnsafePointer<swr_measure_request_v08>) throws -> R) throws -> R {
        if ext.features.count > TextExtension.featuresMax { throw BridgeError.status(-8, "swr_measure_text_v08 (more than \(TextExtension.featuresMax) features)") }
        if ext.fallbackFamilies.count > TextExtension.fallbacksMax { throw BridgeError.status(-8, "swr_measure_text_v08 (more than \(TextExtension.fallbacksMax) fallback families)") }
        if ext.fallbackFamilies.contains(where: { $0.isEmpty }) { throw BridgeError.status(-1, "swr_measure_text_v08 (empty fallback family)") }
        let floats = [ext.weight ?? 0, ext.width, ext.opticalSize, ext.slant, ext.trackingDIP, ext.kerningDIP, ext.baselineOffsetDIP ?? 0]
        if floats.contains(where: { !$0.isFinite }) { throw BridgeError.status(-1, "swr_measure_text_v08 (non-finite value)") }
        if let w = ext.weight, w < 1 || w > 1000 { throw BridgeError.status(-1, "swr_measure_text_v08 (weight outside 1...1000)") }

        var q = swr_measure_request_v08()
        q.struct_size = UInt32(MemoryLayout<swr_measure_request_v08>.size)
        q.flags = ext.baselineOffsetDIP != nil ? UInt32(SWR_M08_BASELINE_OFFSET) : 0
        var base = swr_measure_request()
        base.struct_size = UInt32(MemoryLayout<swr_measure_request>.size)
        let t = arena.string(r.text); base.text = t.ptr; base.text_len = t.len
        let f = arena.string(r.fontFamily); base.font_family = f.ptr; base.font_family_len = f.len
        let l = arena.string(r.locale); base.locale = l.ptr; base.locale_len = l.len
        base.font_weight = r.weight
        base.direction = 0
        base.color = r.color
        base.font_size = r.fontSize
        base.line_height = r.lineHeight
        base.scale = r.scale
        base.max_width = r.maxWidth
        base.lines_out = lines
        base.lines_cap = UInt32(cap)
        q.base = base
        q.weight_f = ext.weight ?? 0
        q.width_axis = ext.width
        q.opsz = ext.opticalSize
        q.slant = ext.slant
        q.tracking_dip = ext.trackingDIP
        q.kerning_dip = ext.kerningDIP
        q.baseline_offset_dip = ext.baselineOffsetDIP ?? 0
        q.italic = ext.italic ? 1 : 0
        q.simulations = ext.simulations.rawValue
        q.feature_count = UInt32(ext.features.count)
        q.features = arena.array(ext.features.map { swr_feature(tag: $0.tag, value: $0.value) })
        let strs: [swr_str] = ext.fallbackFamilies.map { s in
            let c = arena.string(s)
            return swr_str(ptr: c.ptr, len: c.len, reserved: 0)
        }
        q.fallbacks = arena.array(strs)
        q.fallback_count = UInt32(strs.count)
        return try withUnsafePointer(to: &q) { try body($0) }
    }

    /// Per shaped sub-run of a retained run: the face, simulation flags, `.notdef` count. Throws SWR_E_UNSUPPORTED on a pre-0.8 renderer.
    func runFaces(of run: TextRunHandle) throws -> [RunFace] {
        guard let ext = textExtension else { throw unsupported("swr_text_run_faces") }
        var count: UInt32 = 0
        var rc = ext.runFaces(run.raw, nil, 0, &count)
        if rc != 0 { throw BridgeError.status(rc, "swr_text_run_faces") }
        if count == 0 { return [] }
        let buf = UnsafeMutablePointer<swr_run_face>.allocate(capacity: Int(count))
        defer { buf.deallocate() }
        buf.initialize(repeating: swr_run_face(), count: Int(count))
        rc = ext.runFaces(run.raw, buf, count, &count)
        if rc != 0 { throw BridgeError.status(rc, "swr_text_run_faces") }
        return (0..<Int(count)).map { i in
            var c = buf[i]
            return RunFace(utf8Start: c.utf8_start, utf8Len: c.utf8_len, glyphCount: c.glyph_count, notdefCount: c.notdef_count,
                           flags: RunFaceFlags(rawValue: c.flags), weight: c.weight, ascent: c.ascent, descent: c.descent,
                           advance: c.advance, sha256: withUnsafeBytes(of: &c.sha256) { Array($0) },
                           family: cString(&c.family), postScriptName: cString(&c.ps_name),
                           version: cString(&c.version), fileName: cString(&c.file_name))
        }
    }

    /// The face a request resolves to (weight snapped to a named instance). Needs no window. Throws SWR_E_UNSUPPORTED pre-0.8.
    func faceMetrics(family: String, weight: UInt32 = 400, width: UInt32 = 0, italic: Bool = false) throws -> FaceMetrics {
        guard let ext = textExtension else { throw unsupported("swr_font_face_metrics") }
        let utf8 = Array(family.utf8)
        if utf8.isEmpty { throw BridgeError.status(-1, "swr_font_face_metrics (empty family)") }
        var out = swr_face_metrics()
        out.struct_size = UInt32(MemoryLayout<swr_face_metrics>.size)
        let rc = utf8.withUnsafeBufferPointer { ext.faceMetrics($0.baseAddress, UInt32($0.count), weight, width, italic ? 1 : 0, &out) }
        if rc != 0 { throw BridgeError.status(rc, "swr_font_face_metrics") }
        let axisCount = min(Int(out.axis_count), Int(SWR_FACE_AXES_MAX))
        let axes = withUnsafeBytes(of: &out.axes) { raw -> [swr_axis_range] in
            Array(raw.bindMemory(to: swr_axis_range.self).prefix(axisCount))
        }.map { a -> AxisRange in
            let tag = String(decoding: [UInt8(a.tag >> 24 & 0xFF), UInt8(a.tag >> 16 & 0xFF), UInt8(a.tag >> 8 & 0xFF), UInt8(a.tag & 0xFF)], as: UTF8.self)
            return AxisRange(tag: tag, minValue: a.min_value, maxValue: a.max_value, defaultValue: a.default_value)
        }
        return FaceMetrics(found: out.flags & UInt32(SWR_FACE_FOUND) != 0, variable: out.flags & UInt32(SWR_FACE_VARIABLE) != 0,
                           bundled: out.flags & UInt32(SWR_FACE_BUNDLED) != 0, source: FontSource(rawValue: out.source) ?? .fallback,
                           weight: out.weight, style: out.style, simulations: SimulationFlags(rawValue: out.simulations),
                           unitsPerEm: out.units_per_em, hheaAscent: out.hhea_ascent, hheaDescent: out.hhea_descent, hheaLineGap: out.hhea_line_gap,
                           typoAscent: out.typo_ascent, typoDescent: out.typo_descent, typoLineGap: out.typo_line_gap,
                           winAscent: out.win_ascent, winDescent: out.win_descent, capHeight: out.cap_height, xHeight: out.x_height,
                           axes: axes, sha256: withUnsafeBytes(of: &out.sha256) { Array($0) },
                           family: cString(&out.family), postScriptName: cString(&out.ps_name),
                           version: cString(&out.version), fileName: cString(&out.file_name))
    }

    /// Which system families exist, with versions. Needs no window. Throws SWR_E_UNSUPPORTED pre-0.8.
    func systemFontInfo() throws -> SystemFontInfo {
        guard let ext = textExtension else { throw unsupported("swr_system_font_info") }
        var out = swr_system_fonts()
        out.struct_size = UInt32(MemoryLayout<swr_system_fonts>.size)
        let rc = ext.systemFontInfo(&out)
        if rc != 0 { throw BridgeError.status(rc, "swr_system_font_info") }
        let n = Int(SWR_SYSFONT_ENTRIES)
        let entries: [SystemFontEntry] = withUnsafeBytes(of: &out.entries) { raw in
            Array(raw.bindMemory(to: swr_system_font_entry.self).prefix(n))
        }.map { e in
            var e = e
            return SystemFontEntry(name: cString(&e.name), version: cString(&e.version), present: e.present != 0, faceCount: e.face_count)
        }
        let flags = out.flags
        func has(_ bit: UInt32) -> Bool { flags & bit != 0 }
        return SystemFontInfo(segoeUI: has(UInt32(SWR_SYSFONT_SEGOE_UI)), segoeUIVariable: has(UInt32(SWR_SYSFONT_SEGOE_VARIABLE)),
                              cascadiaMono: has(UInt32(SWR_SYSFONT_CASCADIA_MONO)), sitka: has(UInt32(SWR_SYSFONT_SITKA)),
                              segoeUIEmoji: has(UInt32(SWR_SYSFONT_SEGOE_EMOJI)), segoeFluentIcons: has(UInt32(SWR_SYSFONT_SEGOE_FLUENT_ICONS)),
                              familyCount: out.family_count, entries: entries)
    }
}

extension TextExtensionReport {
    init(_ r: swr_measure_result_v08) {
        self.init(applied: TextExtensionApplied(rawValue: r.applied), ignored: TextExtensionIgnored(rawValue: r.ignored),
                  resolvedWeight: r.resolved_weight, resolvedItalic: r.resolved_italic != 0,
                  simulations: SimulationFlags(rawValue: r.simulations))
    }
}
