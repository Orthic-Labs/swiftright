import CryptoKit
import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Factory-only system-image adapter. It accepts provider-rasterized RGBA bytes,
/// then retains one ABI 0.6 image handle per exact ImageReference.
@MainActor final class FactorySystemImageRegistry {
    struct Mapping: Decodable {
        let schema: String
        let mappingVersion: String
        let identity: String
        let provider: String
        let providerVersion: String
        let glyph: String
        let foregroundSemantic: String
        let width: UInt32?
        let height: UInt32?
        let rgbaBase64: String?
        let rgbaSha256: String?
        let status: String
        let licenseStatus: String
    }

    static let mappingFile = "FactorySystemImageAssets.json"
    static let identity = "star.fill"
    static let provider = "Segoe Fluent Icons"
    static let glyph = "E735"
    private let bridge: Bridge
    let mapping: Mapping
    private var handles: [ImageReference: ImageHandle] = [:]

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
        guard mapping.schema == "factory-system-image-provider-map-v1",
              mapping.mappingVersion == "segoe-fluent-icons-star-fill-v1",
              mapping.identity == Self.identity,
              mapping.provider == Self.provider,
              mapping.glyph == Self.glyph,
              mapping.foregroundSemantic == "system.yellow",
              mapping.providerVersion.isEmpty == false,
              mapping.licenseStatus == "unverified" else {
            throw NSError(domain: "FactorySystemImageMappingMismatch", code: 1)
        }
    }

    var isRasterReady: Bool {
        mapping.status == "provider-raster-ready" && mapping.width != nil && mapping.height != nil &&
        mapping.rgbaBase64 != nil && mapping.rgbaSha256 != nil
    }

    func intrinsicSize(for reference: ImageReference) -> LayoutSize {
        guard case .system(Self.identity) = reference,
              let width = mapping.width, let height = mapping.height else { return .zero }
        return LayoutSize(width: CGFloat(width), height: CGFloat(height))
    }

    func handle(for reference: ImageReference) throws -> ImageHandle {
        guard case .system(Self.identity) = reference else {
            throw NSError(domain: "FactorySystemImageReferenceMismatch", code: 1)
        }
        if let handle = handles[reference] { return handle }
        guard isRasterReady,
              let width = mapping.width, let height = mapping.height,
              width > 0, height > 0, width <= 4096, height <= 4096,
              let encoded = mapping.rgbaBase64,
              let expectedHash = mapping.rgbaSha256,
              let data = Data(base64Encoded: encoded) else {
            throw NSError(domain: "FactorySystemImageProviderRasterMissing", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "star.fill requires provider-rasterized RGBA bytes"])
        }
        let expectedBytes = UInt64(width) * UInt64(height) * 4
        guard expectedBytes == UInt64(data.count) else {
            throw NSError(domain: "FactorySystemImageProviderRasterSizeMismatch", code: 1)
        }
        let actualHash = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else {
            throw NSError(domain: "FactorySystemImageProviderRasterHashMismatch", code: 1)
        }
        let handle = try bridge.registerImage(width: width, height: height, rgba: Array(data), stride: width * 4)
        handles[reference] = handle
        print("FACTORY_SYSTEM_IMAGE identity=star.fill provider=Segoe_Fluent_Icons glyph=E735 mappingVersion=segoe-fluent-icons-star-fill-v1 rgbaSha256=\(actualHash) registration=abi-0.6")
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
          case .system(FactorySystemImageRegistry.identity) = reference,
          let sizing = node.imageSizing,
          sizing.isResizable, sizing.scalesToFit,
          sizing.resizingMode == .stretch,
          node.opacity == 1,
          node.frame.width == 32, node.frame.height == 32,
          node.pixelFrame.width > 0, node.pixelFrame.height > 0 else {
        throw NSError(domain: "FactorySystemImageContractMismatch", code: 1)
    }
    let handle = try registry.handle(for: reference)
    return .image(handle, Rect(x: Float(node.pixelFrame.x), y: Float(node.pixelFrame.y),
                                w: Float(node.pixelFrame.width), h: Float(node.pixelFrame.height)))
}
