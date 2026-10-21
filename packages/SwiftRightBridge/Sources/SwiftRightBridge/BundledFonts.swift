import CSwiftRight
import Foundation

// Bundled-font registration (ABI rev 0.7). A renderer at 0.7 shapes a family from bytes the
// host registered; a 0.6 renderer cannot, and says so instead of silently falling back.

public typealias FontRegisterFn = @convention(c) (UnsafePointer<UInt8>?, UInt64, UnsafeMutablePointer<swr_font_info>?) -> Int32
public typealias FontResolveFn = @convention(c) (UnsafePointer<UInt8>?, UInt32, UnsafeMutablePointer<swr_font_resolution>?) -> Int32

/// The two 0.7 font entry points of a renderer's table.
public struct FontEntryPoints {
    public let register: FontRegisterFn
    public let resolve: FontResolveFn
    public init(register: @escaping FontRegisterFn, resolve: @escaping FontResolveFn) {
        self.register = register
        self.resolve = resolve
    }
}

public struct FontRegistrationFlags: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    /// First registration of these bytes.
    public static let new = FontRegistrationFlags(rawValue: UInt32(SWR_FONT_NEW))
    /// The same bytes were registered before; the handle is unchanged.
    public static let duplicate = FontRegistrationFlags(rawValue: UInt32(SWR_FONT_DUPLICATE))
    /// The text system already listed this family name (a bundled family shadowing an installed one).
    public static let systemFamily = FontRegistrationFlags(rawValue: UInt32(SWR_FONT_SYSTEM_FAMILY))
    /// The family was measured before registration; GPUI may keep a cached resolution.
    public static let late = FontRegistrationFlags(rawValue: UInt32(SWR_FONT_LATE))
}

public struct FontRegistration: Equatable {
    public let handle: UInt64
    public let family: String
    public let weight: UInt32
    public let faceCount: UInt32
    public let sha256: [UInt8]
    public let flags: FontRegistrationFlags
    public var sha256Hex: String { sha256.map { String(format: "%02x", $0) }.joined() }
}

public enum FontSource: UInt32 {
    /// Not bundled and not listed: the renderer would shape it with its fallback face.
    case fallback = 0
    /// Shaped from registered bytes.
    case bundled = 1
    /// An installed family the text system lists.
    case system = 2
}

public struct FontResolution: Equatable {
    public let source: FontSource
    public let handle: UInt64
    public let sha256: [UInt8]
}

public extension Bridge {
    /// True when the renderer is ABI 0.7 (it has the font entries).
    var supportsFontRegistration: Bool { fonts != nil }

    /// Registers TTF/OTF/TTC bytes with the renderer for this process (retained until exit: GPUI
    /// cannot unregister). UI thread only, after the window exists (call it from `onReady`).
    /// Throws SWR_E_UNSUPPORTED on an ABI 0.6 renderer.
    func registerFont(_ bytes: [UInt8]) throws -> FontRegistration {
        guard let fonts else { throw BridgeError.status(-15, "swr_font_register (renderer ABI \(revision) has no font registration)") }
        if bytes.isEmpty { throw BridgeError.status(-1, "swr_font_register (empty font)") }
        var info = swr_font_info()
        info.struct_size = UInt32(MemoryLayout<swr_font_info>.size)
        let rc = bytes.withUnsafeBufferPointer { fonts.register($0.baseAddress, UInt64($0.count), &info) }
        if rc != 0 { throw BridgeError.status(rc, "swr_font_register") }
        let family = withUnsafeBytes(of: &info.family) { raw in
            String(decoding: raw.prefix(min(Int(info.family_len), raw.count)), as: UTF8.self)
        }
        let sha = withUnsafeBytes(of: &info.sha256) { Array($0) }
        return FontRegistration(handle: info.font, family: family, weight: info.weight, faceCount: info.face_count,
                                sha256: sha, flags: FontRegistrationFlags(rawValue: info.flags))
    }

    /// Where `family` would be shaped from, without shaping. The negative control for fallback.
    func resolveFont(family: String) throws -> FontResolution {
        guard let fonts else { throw BridgeError.status(-15, "swr_font_resolve (renderer ABI \(revision) has no font registration)") }
        let utf8 = Array(family.utf8)
        if utf8.isEmpty { throw BridgeError.status(-1, "swr_font_resolve (empty family)") }
        var out = swr_font_resolution()
        out.struct_size = UInt32(MemoryLayout<swr_font_resolution>.size)
        let rc = utf8.withUnsafeBufferPointer { fonts.resolve($0.baseAddress, UInt32($0.count), &out) }
        if rc != 0 { throw BridgeError.status(rc, "swr_font_resolve") }
        let sha = withUnsafeBytes(of: &out.sha256) { Array($0) }
        return FontResolution(source: FontSource(rawValue: out.source) ?? .fallback, handle: out.font, sha256: sha)
    }
}

/// The vertical metrics of a font file (`head` unitsPerEm, `hhea` ascent / descent / lineGap), read from the registered
/// bytes. These are CoreText's metrics for the face: SwiftUI `Text` places its baseline at round(ascent) DIP below the line
/// top and lays lines out at round(ascent) + round(descent); the font's lineGap (leading) is not part of the line height
/// (measured on macOS, ImageRenderer, Tinos 13/18/31 pt at 1x/2x/2.5x).
public struct FontFileMetrics: Equatable {
    public let unitsPerEm: UInt16
    public let ascentUnits: Int16
    public let descentUnits: Int16
    public let lineGapUnits: Int16
    /// The face is an italic or oblique one: `head.macStyle` bit 1 or `OS/2.fsSelection` bit 0 (#78).
    public var isItalic = false

    public func ascent(pointSize: Float) -> Float { pointSize * Float(ascentUnits) / Float(unitsPerEm) }
    public func descent(pointSize: Float) -> Float { pointSize * abs(Float(descentUnits)) / Float(unitsPerEm) }
    /// The line height SwiftUI/CoreText gives a single line of this face at `pointSize` (DIP).
    public func lineHeight(pointSize: Float) -> Float { ascent(pointSize: pointSize).rounded() + descent(pointSize: pointSize).rounded() }

    /// Parses TTF/OTF (and the first face of a TTC). Nil when a table is absent or the values are implausible.
    public static func parse(_ bytes: [UInt8]) -> FontFileMetrics? {
        func u16(_ o: Int) -> Int? { o >= 0 && o + 2 <= bytes.count ? Int(bytes[o]) << 8 | Int(bytes[o + 1]) : nil }
        func u32(_ o: Int) -> Int? { o >= 0 && o + 4 <= bytes.count ? Int(bytes[o]) << 24 | Int(bytes[o + 1]) << 16 | Int(bytes[o + 2]) << 8 | Int(bytes[o + 3]) : nil }
        var base = 0
        if bytes.count >= 16, bytes[0] == 0x74, bytes[1] == 0x74, bytes[2] == 0x63, bytes[3] == 0x66 {   // "ttcf"
            guard let first = u32(12) else { return nil }
            base = first
        }
        guard let count = u16(base + 4), count > 0, count <= 512 else { return nil }
        func table(_ tag: String) -> Int? {
            let wanted = Array(tag.utf8)
            for i in 0..<count {
                let row = base + 12 + i * 16
                guard row + 16 <= bytes.count else { return nil }
                if Array(bytes[row..<(row + 4)]) == wanted {
                    guard let offset = u32(row + 8), let length = u32(row + 12), offset <= bytes.count, length <= bytes.count - offset else { return nil }
                    return offset
                }
            }
            return nil
        }
        guard let head = table("head"), let hhea = table("hhea"),
              let units = u16(head + 18), let ascent = u16(hhea + 4), let descent = u16(hhea + 6), let gap = u16(hhea + 8),
              units > 0 else { return nil }
        let a = Int16(truncatingIfNeeded: ascent), d = Int16(truncatingIfNeeded: descent)
        guard a > 0, d != 0 else { return nil }
        var italic = (u16(head + 44).map { $0 & 0x2 != 0 }) ?? false
        if let os2 = table("OS/2"), let selection = u16(os2 + 62), selection & 0x1 != 0 { italic = true }
        return FontFileMetrics(unitsPerEm: UInt16(units), ascentUnits: a, descentUnits: d, lineGapUnits: Int16(truncatingIfNeeded: gap), isItalic: italic)
    }
}

/// The bundled font resources of an app: registers every font file in a resource directory with the
/// renderer, and answers what `Font.custom(_:size:)` names mean. Use it from `onReady`, before the
/// first measurement, so the first shaping of a family already sees the bundled bytes.
public final class BundledFontLibrary {
    public static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]

    public private(set) var registrations: [FontRegistration] = []
    /// lower-cased lookup key (family, file stem) -> provider family.
    private var providerFamilies: [String: String] = [:]
    /// provider family (lower-cased) -> vertical metrics read from the registered bytes.
    private var metricsByFamily: [String: FontFileMetrics] = [:]
    /// lower-cased file stem -> the weight class of the face that file registered (`Tinos-Bold` -> 700): a `Font.custom` name that is a face's own name selects it.
    private var faceWeights: [String: UInt32] = [:]
    /// lower-cased file stem -> that face's own vertical metrics (a bold face can differ from the regular one of its family).
    private var faceMetrics: [String: FontFileMetrics] = [:]
    /// Standardized file path -> its registration: a file is handed to the renderer once per library, however often it is registered.
    private var registeredFiles: [String: FontRegistration] = [:]
    private let bridge: Bridge

    public init(bridge: Bridge) { self.bridge = bridge }

    /// Directories where bundled fonts live, nearest first: `<resource dir>`, `<resource dir>/Fonts`.
    public static func fontFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for dir in [directory, directory.appendingPathComponent("Fonts", isDirectory: true)] {
            let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            out += entries.filter { fontExtensions.contains($0.pathExtension.lowercased()) }
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Registers every font file under `directory`. A file the renderer rejects throws (the app shipped a
    /// broken resource); an ABI 0.6 renderer throws SWR_E_UNSUPPORTED only when there is something to register.
    @discardableResult
    public func registerAll(in directory: URL) throws -> [FontRegistration] {
        var added: [FontRegistration] = []
        for file in Self.fontFiles(in: directory) {
            added.append(try register(file: file))
        }
        return added
    }

    @discardableResult
    public func register(file: URL) throws -> FontRegistration {
        let path = file.standardizedFileURL.path
        if let done = registeredFiles[path] { return done }
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        let reg = try bridge.registerFont([UInt8](data))
        registrations.append(reg)
        let stem = file.deletingPathExtension().lastPathComponent.lowercased()
        if let metrics = FontFileMetrics.parse([UInt8](data)) {
            // the family's metrics stay the first (regular-most) face's: a later face of the same family does not replace them
            if metricsByFamily[reg.family.lowercased()] == nil || reg.weight == 400 { metricsByFamily[reg.family.lowercased()] = metrics }
            faceMetrics[stem] = metrics
        }
        providerFamilies[reg.family.lowercased()] = reg.family
        providerFamilies[stem] = reg.family
        faceWeights[stem] = reg.weight
        registeredFiles[path] = reg
        return reg
    }

    /// The renderer family a `Font.custom` name selects, or nil when no bundled font answers to it. Accepts the
    /// family ("Tinos"), a PostScript-style name ("Tinos-Regular") or the file stem.
    public func providerFamily(forCustomName name: String) -> String? {
        let key = name.lowercased()
        if let hit = providerFamilies[key] { return hit }
        if let dash = key.firstIndex(of: "-"), let hit = providerFamilies[String(key[..<dash])] { return hit }
        return nil
    }

    /// The vertical metrics (hhea) of the bundled face a `Font.custom` name selects, nil when none answers to it or the
    /// bytes carried no usable tables. A name that is a face's own (`Tinos-Bold`) answers with that face's metrics.
    public func metrics(forCustomName name: String) -> FontFileMetrics? {
        if let own = faceMetrics[name.lowercased()] { return own }
        return providerFamily(forCustomName: name).flatMap { metricsByFamily[$0.lowercased()] }
    }

    /// The weight class (100...900) a `Font.custom` name asks for by itself, nil when the name is a family (or no bundled font answers to it) and the face is left to
    /// `.weight(_:)`. SwiftUI selects a face by its PostScript name: `Font.custom("Tinos-Bold", size: 17)` is the bold face with no `.weight` at all. A face named by its file
    /// stem answers with the weight class its file registered; a `Family-Suffix` name whose suffix is a weight word (`Bold`, `SemiBold`, `Light`...) answers with that weight when the
    /// family is bundled. An explicit `.weight(_:)` on the Font still wins (the caller applies this only when none was given).
    public func weight(forCustomName name: String) -> UInt32? {
        let key = name.lowercased()
        if let own = faceWeights[key] { return own }
        guard providerFamily(forCustomName: name) != nil else { return nil }
        return Self.weightClass(inFaceName: name)
    }

    /// True when a `Font.custom` name selects an italic face by itself (#78): a bundled file's stem whose face is italic (`Tinos-Italic`), or a `Family-Suffix` name whose suffix says
    /// italic or oblique, when the family is bundled. False for a family name or a regular face.
    public func isItalic(forCustomName name: String) -> Bool {
        let key = name.lowercased()
        if let own = faceMetrics[key] { return own.isItalic }
        guard providerFamily(forCustomName: name) != nil, let dash = key.lastIndex(of: "-") else { return false }
        let suffix = key[key.index(after: dash)...]
        return suffix.contains("italic") || suffix.contains("oblique")
    }

    /// The weight class a `Family-Suffix` face name's suffix names (`Tinos-SemiBold` -> 600), nil when there is no dash or the suffix is not a weight word.
    public static func weightClass(inFaceName name: String) -> UInt32? {
        let key = name.lowercased()
        guard let dash = key.lastIndex(of: "-") else { return nil }
        return weightWords[String(key[key.index(after: dash)...]).replacingOccurrences(of: "_", with: "")]
    }

    static let weightWords: [String: UInt32] = [
        "thin": 100, "hairline": 100, "ultralight": 200, "extralight": 200, "light": 300, "regular": 400, "book": 400, "roman": 400, "medium": 500,
        "semibold": 600, "demibold": 600, "bold": 700, "extrabold": 800, "ultrabold": 800, "heavy": 800, "black": 900,
    ]
}
