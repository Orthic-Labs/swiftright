import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Name-driven provider adapter. ABI 0.6 accepts RGBA image handles, so provider
/// raster evidence is represented as bounded glyph coverage bytes, then sized & tinted
/// from each resolved runtime Image node.
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
    struct SymbolProvider: Decodable {
        let provider: String
        let providerVersion: String
        let glyph: String
        let glyphIndex: UInt32?
        let foregroundSemantic: String
        let width: UInt32
        let height: UInt32
        let rgbaBytes: UInt64
        let rgbaSha256: String
        let rgbaBase64: String
        let status: String
        let glyphMetrics: GlyphMetrics?
        let fontMetrics: GlyphMetrics?
        let rasterization: Rasterization?
    }
    struct ProviderPolicy: Decodable {
        let kind: String
        let resolution: String
        let parity: String
        let maxSymbols: UInt32
    }
    struct Mapping: Decodable {
        let schema: String
        let mappingVersion: String
        let providerPolicy: ProviderPolicy
        let symbols: [String: SymbolProvider]
    }

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

    init(_ bridge: Bridge) throws {
        self.bridge = bridge
        let url = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent(Self.mappingFile)
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
              mapping.symbols.count > 0,
              mapping.symbols.count <= Int(mapping.providerPolicy.maxSymbols) else {
            throw NSError(domain: "FactorySystemImageProviderPolicyMismatch", code: 1)
        }
        for (name, entry) in mapping.symbols {
            guard !name.isEmpty, name.utf8.count <= 128,
                  !entry.provider.isEmpty, !entry.providerVersion.isEmpty,
                  !entry.glyph.isEmpty, entry.width > 0, entry.width <= 4096,
                  entry.height > 0, entry.height <= 4096,
                  entry.rgbaBytes == UInt64(entry.width) * UInt64(entry.height) * 4,
                  entry.status == "provider-raster-ready",
                  entry.rgbaBase64.utf8.count <= 64 * 1024 * 1024 else {
                throw NSError(domain: "FactorySystemImageProviderEntryInvalid", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: name])
            }
        }
        print("FACTORY_SYSTEM_IMAGE_PROVIDER_POLICY kind=\(mapping.providerPolicy.kind) resolution=\(mapping.providerPolicy.resolution) parity=\(mapping.providerPolicy.parity) symbols=\(mapping.symbols.count)")
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
        return LayoutSize(width: CGFloat(entry.width), height: CGFloat(entry.height))
    }

    func handle(for reference: ImageReference, tint: UInt32, width targetWidth: UInt32,
                height targetHeight: UInt32) throws -> ImageHandle {
        let (name, entry) = try provider(for: reference)
        guard targetWidth > 0, targetHeight > 0, targetWidth <= 4096, targetHeight <= 4096 else {
            throw NSError(domain: "FactorySystemImageTargetSizeInvalid", code: 1)
        }
        let key = HandleKey(reference: reference, tint: tint, width: targetWidth, height: targetHeight)
        if let handle = handles[key] { return handle }
        guard let data = Data(base64Encoded: entry.rgbaBase64),
              UInt64(data.count) == entry.rgbaBytes else {
            throw NSError(domain: "FactorySystemImageProviderRasterSizeMismatch", code: 1)
        }
        let actualHash = FactorySHA256.hash(data: data)
        guard actualHash == entry.rgbaSha256 else {
            throw NSError(domain: "FactorySystemImageProviderRasterHashMismatch", code: 1)
        }
        let sourceWidth = Int(entry.width), sourceHeight = Int(entry.height)
        let destinationWidth = Int(targetWidth), destinationHeight = Int(targetHeight)
        guard destinationWidth * destinationHeight <= (64 * 1024 * 1024) / 4 else {
            throw NSError(domain: "FactorySystemImageTargetSizeTooLarge", code: 1)
        }
        var tinted = Array(repeating: UInt8(0), count: destinationWidth * destinationHeight * 4)
        let red = UInt8((tint >> 24) & 0xff), green = UInt8((tint >> 16) & 0xff)
        let blue = UInt8((tint >> 8) & 0xff), tintAlpha = UInt32(tint & 0xff)
        var nonZeroCoverage = 0
        var maxCoverage = 0
        // Provider rasterizer supplies source alpha coverage; ABI 0.6 exposes
        // target-sized RGBA registration, so coverage is bounded to target pixels.
        for y in 0..<destinationHeight {
            let sourceY = (Float(y) + 0.5) * Float(sourceHeight) / Float(destinationHeight) - 0.5
            let yFloor = sourceY.rounded(.down), y0 = max(0, min(sourceHeight - 1, Int(yFloor)))
            let y1 = max(0, min(sourceHeight - 1, y0 + 1)), fy = max(0, min(1, sourceY - yFloor))
            for x in 0..<destinationWidth {
                let sourceX = (Float(x) + 0.5) * Float(sourceWidth) / Float(destinationWidth) - 0.5
                let xFloor = sourceX.rounded(.down), x0 = max(0, min(sourceWidth - 1, Int(xFloor)))
                let x1 = max(0, min(sourceWidth - 1, x0 + 1)), fx = max(0, min(1, sourceX - xFloor))
                func alpha(_ sx: Int, _ sy: Int) -> Float { Float(data[(sy * sourceWidth + sx) * 4 + 3]) }
                let top = alpha(x0, y0) * (1 - fx) + alpha(x1, y0) * fx
                let bottom = alpha(x0, y1) * (1 - fx) + alpha(x1, y1) * fx
                let coverage = UInt32((top * (1 - fy) + bottom * fy).rounded())
                if coverage > 0 { nonZeroCoverage += 1 }; maxCoverage = max(maxCoverage, Int(coverage))
                let index = (y * destinationWidth + x) * 4
                tinted[index] = red; tinted[index + 1] = green; tinted[index + 2] = blue
                tinted[index + 3] = UInt8((coverage * tintAlpha + 127) / 255)
            }
        }
        guard nonZeroCoverage > 0 else { throw NSError(domain: "FactorySystemImageEmptyCoverage", code: 1) }
        let handle = try bridge.registerImage(width: targetWidth, height: targetHeight, rgba: tinted, stride: targetWidth * 4)
        handles[key] = handle
        let metrics = entry.fontMetrics ?? entry.glyphMetrics
        print("FACTORY_SYSTEM_IMAGE name=\(name) provider=\(entry.provider) providerVersion=\(entry.providerVersion) glyph=\(entry.glyph) glyphIndex=\(entry.glyphIndex.map(String.init) ?? \"nil\") sourceBounds=\(entry.width)x\(entry.height) targetBounds=\(targetWidth)x\(targetHeight) tintRGBA=\(String(format: \"%08x\", tint)) nonZeroCoverage=\(nonZeroCoverage) maxCoverage=\(maxCoverage) fontUnitsPerEm=\(metrics?.designUnitsPerEm.map(String.init) ?? \"nil\") rasterization=\(entry.rasterization?.kind ?? \"provider-raster\") parity=\(mapping.providerPolicy.parity) registration=abi-0.6")
        return handle
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
          registry.supports(reference),
          let sizing = node.imageSizing,
          sizing.isResizable, sizing.scalesToFit,
          sizing.resizingMode == .stretch,
          node.pixelFrame.width > 0, node.pixelFrame.height > 0 else {
        throw NSError(domain: "FactorySystemImageContractMismatch", code: 1)
    }
    let tint = try factoryResolvedFill(node.style.foreground ?? .semantic("system.yellow"), opacity: node.opacity)
    let targetWidth = UInt32(max(1, Int(node.pixelFrame.width.rounded())))
    let targetHeight = UInt32(max(1, Int(node.pixelFrame.height.rounded())))
    let handle = try registry.handle(for: reference, tint: tint, width: targetWidth, height: targetHeight)
    print("FACTORY_SYSTEM_IMAGE_FRAME name=\(reference.name) widthPX=\(node.pixelFrame.width) heightPX=\(node.pixelFrame.height) tintRGBA=\(String(format: \"%08x\", tint))")
    return .image(handle, Rect(x: Float(node.pixelFrame.x), y: Float(node.pixelFrame.y),
                                w: Float(node.pixelFrame.width), h: Float(node.pixelFrame.height)))
}
