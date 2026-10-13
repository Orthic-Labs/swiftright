import Foundation
import SwiftRightRuntime

/// The shipped `Image(systemName:)` symbol table: name -> substitute glyph provider (a Windows icon font glyph) plus the
/// Mac-measured SF Symbol layout of that name (intrinsic size, scale-class ink model, measured ink overrides).
/// Windows has no SF Symbols: provider identity is observable and never implies SF Symbol glyph parity.
/// The JSON source is `Assets/SystemImageAssets.json`; `SystemImageTableData.swift` embeds it (scripts/embed-assets.py)
/// so the table ships inside the module with no file lookup at run time.
public struct SystemImageTable: Decodable {
    public struct GlyphMetrics: Decodable {
        public let designUnitsPerEm: UInt32?
        public let ascent: Int32?
        public let descent: Int32?
        public let lineGap: Int32?
    }
    public struct Rasterization: Decodable {
        public let kind: String
        public let textureType: String?
        public let fontEmSize: Float?
        public let source: String?
    }
    /// Mac-measured SF Symbol layout metrics (factory/tools/symbol-metrics); never outlines.
    public struct Layout: Decodable {
        public let aspect: Double
        public let inkRect: [Double]
        public let intrinsicSize: [Double]
        public let sourceOversample: UInt32?
        public let fitIntrinsicSize: [Double]?
        /// SwiftUI sizes a resizable symbol by an intrinsic box that depends only on the screen-scale CLASS (1x below
        /// scale 2, 2x from 2), never on the frame; the ink fractions and edge biases predict the half-coverage ink box
        /// for any frame (factory/tools/symbol-metrics/fit-layout.py).
        public struct ScaleClass: Decodable {
            public let scaleClass: String
            public let minScale: Double
            public let maxScaleExclusive: Double?
            public let fitIntrinsicSize: [Double]
            public let inkFractions: [Double]
            public let inkBias: [Double]
        }
        /// A measured Mac ink box the class model mispredicts (sharp-tip phase); used only on an exact (scale, view size)
        /// match. It is a recorded measurement of that one size, not a rule: a size served by an override is evidence of
        /// the measurement, never of generalisation.
        public struct InkOverride: Decodable {
            public let scale: Double
            public let viewFramePx: [Int]
            public let inkBoxPx: [Int]
        }
        public let scaleClasses: [ScaleClass]?
        public let inkOverrides: [InkOverride]?

        public func scaleClass(scale: Double) -> ScaleClass? {
            scaleClasses?.first(where: { scale >= $0.minScale && ($0.maxScaleExclusive.map { scale < $0 } ?? true)
                && $0.fitIntrinsicSize.count == 2 && $0.inkFractions.count == 4 && $0.inkBias.count == 4 })
        }
        /// Intrinsic size SwiftUI fits this symbol by at the given screen scale.
        public func fitIntrinsic(scale: Double) -> [Double]? { scaleClass(scale: scale)?.fitIntrinsicSize ?? fitIntrinsicSize }

        /// The measured override for this exact (scale, view size), if any.
        public func inkOverride(scale: Double, widthPx: UInt32, heightPx: UInt32) -> InkOverride? {
            inkOverrides?.first(where: { $0.viewFramePx.count == 4 && $0.inkBoxPx.count == 4 && abs($0.scale - scale) < 1e-6
                && $0.viewFramePx[2] == Int(widthPx) && $0.viewFramePx[3] == Int(heightPx) })
        }

        /// Mac half-coverage pixel ink box (relative to the view frame) and where it came from: a measured override for
        /// this exact view size, else the scale-class model's prediction for any size.
        public func deviceInkBox(scale: Double, widthPx: UInt32, heightPx: UInt32) -> (box: SystemImageDeviceInkBox, source: String)? {
            guard scale > 0 else { return nil }
            if let hit = inkOverride(scale: scale, widthPx: widthPx, heightPx: heightPx) {
                let box = SystemImageDeviceInkBox(left: hit.inkBoxPx[0], top: hit.inkBoxPx[1], right: hit.inkBoxPx[2], bottom: hit.inkBoxPx[3])
                if box.isValid { return (box, "measured-override") }
            }
            return metrics(scale: scale)?.predictedInkBox(widthPx: Int(widthPx), heightPx: Int(heightPx)).map { ($0, "scale-class-model") }
        }
        public func metrics(scale: Double) -> SystemImageLayoutMetrics? {
            guard let c = scaleClass(scale: scale), c.fitIntrinsicSize[1] > 0 else { return metrics }
            let m = SystemImageLayoutMetrics(aspect: c.fitIntrinsicSize[0] / c.fitIntrinsicSize[1], inkLeft: c.inkFractions[0], inkTop: c.inkFractions[1],
                                             inkRight: c.inkFractions[2], inkBottom: c.inkFractions[3], inkBias: c.inkBias)
            return m.isValid ? m : metrics
        }
        public var metrics: SystemImageLayoutMetrics? {
            guard inkRect.count == 4 else { return nil }
            let m = SystemImageLayoutMetrics(aspect: aspect, inkLeft: inkRect[0], inkTop: inkRect[1],
                                             inkRight: inkRect[2], inkBottom: inkRect[3])
            return m.isValid ? m : nil
        }
    }
    public struct Symbol: Decodable {
        public let provider: String
        public let providerVersion: String
        public let glyph: String
        public let glyphIndex: UInt32?
        public let foregroundSemantic: String
        public let width: UInt32
        public let height: UInt32
        public let status: String
        public let glyphMetrics: GlyphMetrics?
        public let fontMetrics: GlyphMetrics?
        public let rasterization: Rasterization?
        public let layout: Layout?
    }
    public struct ProviderPolicy: Decodable {
        public let kind: String
        public let resolution: String
        public let parity: String
        public let maxSymbols: UInt32
        public let rasterization: String
        public let cache: String
    }
    public let schema: String
    public let mappingVersion: String
    public let providerPolicy: ProviderPolicy
    public let symbols: [String: Symbol]

    public enum TableError: Error, Equatable {
        case providerPolicyMismatch
        case entryInvalid(String)
        case tooLarge
    }

    /// Decodes and validates a table. Bounded input; every entry is checked.
    public static func decode(_ data: Data) throws -> SystemImageTable {
        guard data.count <= 64 * 1024 * 1024 else { throw TableError.tooLarge }
        let table = try JSONDecoder().decode(SystemImageTable.self, from: data)
        guard table.schema == "factory-system-image-provider-map-v2",
              table.mappingVersion == "named-glyph-provider-v1",
              table.providerPolicy.kind == "name-to-glyph-provider",
              table.providerPolicy.resolution == "provider-table",
              table.providerPolicy.parity == "substitute-provider-unverified",
              table.providerPolicy.rasterization == "live-native-gdi-glyph-outline",
              table.providerPolicy.cache == "none",
              !table.symbols.isEmpty,
              table.symbols.count <= Int(table.providerPolicy.maxSymbols) else {
            throw TableError.providerPolicyMismatch
        }
        for (name, entry) in table.symbols {
            guard !name.isEmpty, name.utf8.count <= 128,
                  !entry.provider.isEmpty, !entry.providerVersion.isEmpty,
                  !entry.glyph.isEmpty, entry.width > 0, entry.width <= 4096,
                  entry.height > 0, entry.height <= 4096,
                  entry.status == "provider-live-declared",
                  entry.layout == nil || (entry.layout!.metrics != nil && entry.layout!.intrinsicSize.count == 2
                    && entry.layout!.intrinsicSize.allSatisfy { $0.isFinite && $0 > 0 }
                    && (1...8).contains(entry.layout!.sourceOversample ?? 1)) else {
                throw TableError.entryInvalid(name)
            }
        }
        return table
    }

    /// The table every SwiftRight app ships with.
    public static func standard() throws -> SystemImageTable {
        try decode(Data(SystemImageTableData.json.utf8))
    }
}
