import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Name-driven live provider adapter. ABI 0.6 receives only RGBA handles; glyph
/// coverage is generated at current runtime size through shared WinSDK provider.
@MainActor final class FactorySystemImageRegistry {
    struct GlyphMetrics: Decodable {
        let designUnitsPerEm: UInt32?
        let ascent: Int32?
        let descent: Int32?
        let lineGap: Int32?
    }
    struct Rasterization: Decodable {
        let kind: String
        let textureType: String?
        let fontEmSize: Float?
        let source: String?
    }
    /// Mac-measured SF Symbol layout metrics (factory/tools/symbol-metrics); never outlines.
    struct Layout: Decodable {
        let aspect: Double
        let inkRect: [Double]
        let intrinsicSize: [Double]
        let sourceOversample: UInt32?
        let fitIntrinsicSize: [Double]?
        /// SwiftUI sizes a resizable symbol by an intrinsic box that depends only on the screen-scale CLASS (1x below
        /// scale 2, 2x from 2), never on the frame; the ink fractions and edge biases predict the half-coverage ink box
        /// for any frame (factory/tools/symbol-metrics/fit-layout.py).
        struct ScaleClass: Decodable {
            let scaleClass: String
            let minScale: Double
            let maxScaleExclusive: Double?
            let fitIntrinsicSize: [Double]
            let inkFractions: [Double]
            let inkBias: [Double]
        }
        /// A measured Mac ink box the class model mispredicts (sharp-tip phase); used only on an exact (scale, view size) match.
        struct InkOverride: Decodable {
            let scale: Double
            let viewFramePx: [Int]
            let inkBoxPx: [Int]
        }
        let scaleClasses: [ScaleClass]?
        let inkOverrides: [InkOverride]?
        func scaleClass(scale: Double) -> ScaleClass? {
            scaleClasses?.first(where: { scale >= $0.minScale && ($0.maxScaleExclusive.map { scale < $0 } ?? true)
                && $0.fitIntrinsicSize.count == 2 && $0.inkFractions.count == 4 && $0.inkBias.count == 4 })
        }
        /// Intrinsic size SwiftUI fits this symbol by at the given screen scale.
        func fitIntrinsic(scale: Double) -> [Double]? { scaleClass(scale: scale)?.fitIntrinsicSize ?? fitIntrinsicSize }
        /// Mac half-coverage pixel ink box (relative to the view frame): a measured override for this exact view size,
        /// else the scale-class model's prediction for any size.
        func deviceInkBox(scale: Double, widthPx: UInt32, heightPx: UInt32) -> SystemImageDeviceInkBox? {
            guard scale > 0 else { return nil }
            if let hit = inkOverrides?.first(where: { $0.viewFramePx.count == 4 && $0.inkBoxPx.count == 4 && abs($0.scale - scale) < 1e-6
                    && $0.viewFramePx[2] == Int(widthPx) && $0.viewFramePx[3] == Int(heightPx) }) {
                let box = SystemImageDeviceInkBox(left: hit.inkBoxPx[0], top: hit.inkBoxPx[1], right: hit.inkBoxPx[2], bottom: hit.inkBoxPx[3])
                if box.isValid { return box }
            }
            return metrics(scale: scale)?.predictedInkBox(widthPx: Int(widthPx), heightPx: Int(heightPx))
        }
        func metrics(scale: Double) -> SystemImageLayoutMetrics? {
            guard let c = scaleClass(scale: scale), c.fitIntrinsicSize[1] > 0 else { return metrics }
            let m = SystemImageLayoutMetrics(aspect: c.fitIntrinsicSize[0] / c.fitIntrinsicSize[1], inkLeft: c.inkFractions[0], inkTop: c.inkFractions[1],
                                             inkRight: c.inkFractions[2], inkBottom: c.inkFractions[3], inkBias: c.inkBias)
            return m.isValid ? m : metrics
        }
        var metrics: SystemImageLayoutMetrics? {
            guard inkRect.count == 4 else { return nil }
            let m = SystemImageLayoutMetrics(aspect: aspect, inkLeft: inkRect[0], inkTop: inkRect[1],
                                             inkRight: inkRect[2], inkBottom: inkRect[3])
            return m.isValid ? m : nil
        }
    }
    struct SymbolProvider: Decodable {
        let provider: String
        let providerVersion: String
        let glyph: String
        let glyphIndex: UInt32?
        let foregroundSemantic: String
        let width: UInt32
        let height: UInt32
        let status: String
        let glyphMetrics: GlyphMetrics?
        let fontMetrics: GlyphMetrics?
        let rasterization: Rasterization?
        let layout: Layout?
    }
    struct ProviderPolicy: Decodable {
        let kind: String
        let resolution: String
        let parity: String
        let maxSymbols: UInt32
        let rasterization: String
        let cache: String
    }
    struct Mapping: Decodable {
        let schema: String
        let mappingVersion: String
        let providerPolicy: ProviderPolicy
        let symbols: [String: SymbolProvider]
    }

    /// Symbols overflow their frames by a pixel or two; the raster canvas keeps that ink.
    static let overflowInset: UInt32 = 4
    static let mappingFile = "FactorySystemImageAssets.json"
    private let bridge: Bridge
    let mapping: Mapping
    private struct HandleKey: Hashable {
        let reference: ImageReference
        let tint: UInt32
        let width: UInt32
        let height: UInt32
    }
    private var handles: [HandleKey: ImageHandle] = [:]
    /// Screen scale of the owned window; selects the Mac device-pixel ink calibration.
    var scale: Double = 1

    init(_ bridge: Bridge) throws {
        self.bridge = bridge
        // Next to the executable, else in the package root above a SwiftPM scratch layout
        // (<package>/scratch/<triple>/release/FactoryProbe.exe), so a plain SwiftPM build needs no copy step.
        var directory = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        var url = directory.appendingPathComponent(Self.mappingFile)
        for _ in 0..<5 where !FileManager.default.fileExists(atPath: url.path) {
            directory = directory.deletingLastPathComponent()
            url = directory.appendingPathComponent(Self.mappingFile)
        }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "FactorySystemImageMappingMissing", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: url.path])
        }
        let fileBytes = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard let fileBytes, fileBytes.uint64Value <= 64 * 1024 * 1024 else {
            throw NSError(domain: "FactorySystemImageMappingTooLarge", code: 1)
        }
        mapping = try JSONDecoder().decode(Mapping.self, from: Data(contentsOf: url))
        guard mapping.schema == "factory-system-image-provider-map-v2",
              mapping.mappingVersion == "named-glyph-provider-v1",
              mapping.providerPolicy.kind == "name-to-glyph-provider",
              mapping.providerPolicy.resolution == "provider-table",
              mapping.providerPolicy.parity == "substitute-provider-unverified",
              mapping.providerPolicy.rasterization == "live-native-gdi-glyph-outline",
              mapping.providerPolicy.cache == "none",
              !mapping.symbols.isEmpty,
              mapping.symbols.count <= Int(mapping.providerPolicy.maxSymbols) else {
            throw NSError(domain: "FactorySystemImageProviderPolicyMismatch", code: 1)
        }
        for (name, entry) in mapping.symbols {
            guard !name.isEmpty, name.utf8.count <= 128,
                  !entry.provider.isEmpty, !entry.providerVersion.isEmpty,
                  !entry.glyph.isEmpty, entry.width > 0, entry.width <= 4096,
                  entry.height > 0, entry.height <= 4096,
                  entry.status == "provider-live-declared",
                  entry.layout == nil || (entry.layout!.metrics != nil && entry.layout!.intrinsicSize.count == 2
                    && entry.layout!.intrinsicSize.allSatisfy { $0.isFinite && $0 > 0 }
                    && (1...8).contains(entry.layout!.sourceOversample ?? 1)) else {
                throw NSError(domain: "FactorySystemImageProviderEntryInvalid", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: name])
            }
        }
        print("FACTORY_SYSTEM_IMAGE_PROVIDER_POLICY kind=\(mapping.providerPolicy.kind) resolution=\(mapping.providerPolicy.resolution) rasterization=\(mapping.providerPolicy.rasterization) cache=\(mapping.providerPolicy.cache) parity=\(mapping.providerPolicy.parity) symbols=\(mapping.symbols.count)")
    }

    private func provider(for reference: ImageReference) throws -> (String, SymbolProvider) {
        guard case .system(let name) = reference, name.utf8.count <= 128,
              let entry = mapping.symbols[name] else {
            throw NSError(domain: "FactorySystemImageProviderEntryMissing", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: reference.name])
        }
        return (name, entry)
    }

    func supports(_ reference: ImageReference) -> Bool {
        guard case .system(let name) = reference else { return false }
        return mapping.symbols[name] != nil
    }

    func intrinsicSize(for reference: ImageReference) -> LayoutSize {
        guard let (_, entry) = try? provider(for: reference) else { return .zero }
        if let layout = entry.layout {   // SF Symbol intrinsic size measured on the Mac
            return LayoutSize(width: CGFloat(layout.intrinsicSize[0]), height: CGFloat(layout.intrinsicSize[1]))
        }
        return LayoutSize(width: CGFloat(entry.width), height: CGFloat(entry.height))
    }

    /// What SwiftUI fits `resizable().scaledToFit()` symbols by (see `Graph.imageFitIntrinsicSize`).
    func fitIntrinsicSize(for reference: ImageReference) -> LayoutSize? {
        guard let (_, entry) = try? provider(for: reference), let size = entry.layout?.fitIntrinsic(scale: scale),
              size.count == 2, size.allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        return LayoutSize(width: CGFloat(size[0]), height: CGFloat(size[1]))
    }

    func handle(for reference: ImageReference, tint: UInt32, width targetWidth: UInt32,
                height targetHeight: UInt32) throws -> ImageHandle {
        let (name, entry) = try provider(for: reference)
        guard targetWidth > 0, targetHeight > 0, targetWidth <= 4096, targetHeight <= 4096 else {
            throw NSError(domain: "FactorySystemImageTargetSizeInvalid", code: 1)
        }
        let key = HandleKey(reference: reference, tint: tint, width: targetWidth, height: targetHeight)
        if let handle = handles[key] { return handle }
        guard let glyph = UInt32(entry.glyph.replacingOccurrences(of: "0x", with: ""), radix: 16) else {
            throw NSError(domain: "FactorySystemImageGlyphEncodingInvalid", code: 1)
        }
        let descriptor = FactorySystemImageGlyphDescriptor(
            name: name, providerFamily: entry.provider, providerVersion: entry.providerVersion,
            glyph: glyph, foregroundSemantic: entry.foregroundSemantic,
            parity: mapping.providerPolicy.parity)
        let raster = try FactorySystemImageProvider.rasterize(descriptor, width: targetWidth,
                                                               height: targetHeight, tint: tint,
                                                               layout: entry.layout?.metrics(scale: scale),
                                                               deviceInk: entry.layout?.deviceInkBox(scale: scale, widthPx: targetWidth, heightPx: targetHeight),
                                                               inset: entry.layout == nil ? 0 : Self.overflowInset,
                                                               oversample: entry.layout?.sourceOversample ?? 1)
        let handle = try bridge.registerImage(width: raster.width, height: raster.height,
                                              rgba: raster.rgba, stride: raster.width * 4)
        handles[key] = handle
        let metrics = entry.fontMetrics ?? entry.glyphMetrics
        print("FACTORY_SYSTEM_IMAGE name=\(name) provider=\(entry.provider) providerVersion=\(entry.providerVersion) glyph=\(entry.glyph) sourceBounds=\(raster.glyphWidth)x\(raster.glyphHeight) targetBounds=\(raster.width)x\(raster.height) renderedBounds=\(raster.renderedWidth)x\(raster.renderedHeight) layoutMetrics=\(entry.layout == nil ? "none" : "mac-measured") placement=\(raster.placement) halfCoverageBox=\(raster.halfCoverageBox) macInkBox=\(raster.macInkBox) deviceInkMatched=\(raster.deviceInkMatched) inkRect=\(raster.inkRect) tintRGBA=\(String(format: "%08x", tint)) nonZeroCoverage=\(raster.nonZeroCoverage) maxCoverage=\(raster.maxCoverage) fontHeight=\(raster.fontHeight) fontAscent=\(raster.fontAscent) averageCharWidth=\(raster.averageCharWidth) cellIncrement=\(raster.cellIncrementX),\(raster.cellIncrementY) selectedFace=\(raster.selectedFace) glyphOrigin=\(raster.glyphOriginX),\(raster.glyphOriginY) declaredUnitsPerEm=\(metrics?.designUnitsPerEm.map(String.init) ?? "nil") rasterization=live-gdi-getglyphoutlinew parity=\(mapping.providerPolicy.parity) registration=abi-0.6")
        return handle
    }

    /// Canvas margin (px) around the frame for a symbol with layout metrics.
    func canvasInset(for reference: ImageReference) -> Float {
        guard let (_, entry) = try? provider(for: reference), entry.layout != nil else { return 0 }
        return Float(Self.overflowInset)
    }

    func releaseAll() {
        for handle in handles.values { _ = bridge.release(handle) }
        handles.removeAll(keepingCapacity: false)
    }
}

@MainActor func factorySystemImagePrimitive(
    _ node: ResolvedNode,
    registry: FactorySystemImageRegistry
) throws -> Primitive {
    guard node.kind == "Image", let reference = node.image,
          registry.supports(reference), let sizing = node.imageSizing,
          sizing.isResizable, sizing.scalesToFit,
          sizing.resizingMode == .stretch,
          node.pixelFrame.width > 0, node.pixelFrame.height > 0 else {
        throw NSError(domain: "FactorySystemImageContractMismatch", code: 1)
    }
    let tint = try factoryResolvedFill(node.style.foreground ?? .semantic("system.yellow"), opacity: node.opacity)
    let targetWidth = UInt32(max(1, node.pixelFrame.width))
    let targetHeight = UInt32(max(1, node.pixelFrame.height))
    let handle = try registry.handle(for: reference, tint: tint, width: targetWidth, height: targetHeight)
    let inset = registry.canvasInset(for: reference)
    print("FACTORY_SYSTEM_IMAGE_FRAME name=\(reference.name) xPX=\(node.pixelFrame.x) yPX=\(node.pixelFrame.y) widthPX=\(node.pixelFrame.width) heightPX=\(node.pixelFrame.height) canvasInsetPX=\(Int(inset)) tintRGBA=\(String(format: "%08x", tint))")
    // GPUI scales logical bounds by the display scale in f32, then floors the origin and ceils the size, so an
    // integral device-pixel rect can stretch by a whole pixel (e.g. 128 px -> 129). Nudge it inside its pixel cell.
    let guardBand: Float = 1.0 / 64
    return .image(handle, Rect(x: Float(node.pixelFrame.x) - inset + guardBand, y: Float(node.pixelFrame.y) - inset + guardBand,
                                w: Float(node.pixelFrame.width) + 2 * inset - 2 * guardBand, h: Float(node.pixelFrame.height) + 2 * inset - 2 * guardBand))
}
