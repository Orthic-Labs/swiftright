import CryptoKit
import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Factory-only system-image adapter. It accepts provider-rasterized RGBA bytes,
/// then retains one ABI 0.6 image handle per exact ImageReference+tint pair.
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

    func handle(for reference: ImageReference, tint: UInt32, width targetWidth: UInt32,
                height targetHeight: UInt32) throws -> ImageHandle {
        guard case .system(Self.identity) = reference else {
            throw NSError(domain: "FactorySystemImageReferenceMismatch", code: 1)
        }
        guard targetWidth > 0, targetHeight > 0, targetWidth <= 4096, targetHeight <= 4096 else {
            throw NSError(domain: "FactorySystemImageTargetSizeInvalid", code: 1)
        }
        let key = HandleKey(reference: reference, tint: tint, width: targetWidth, height: targetHeight)
        if let handle = handles[key] { return handle }
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
        let sourceWidth = Int(width)
        let sourceHeight = Int(height)
        let destinationWidth = Int(targetWidth)
        let destinationHeight = Int(targetHeight)
        var tinted = Array(repeating: UInt8(0), count: destinationWidth * destinationHeight * 4)
        let red = UInt8((tint >> 24) & 0xff)
        let green = UInt8((tint >> 16) & 0xff)
        let blue = UInt8((tint >> 8) & 0xff)
        let tintAlpha = UInt32(tint & 0xff)
        for y in 0..<destinationHeight {
            let sourceY = (Float(y) + 0.5) * Float(sourceHeight) / Float(destinationHeight) - 0.5
            let yFloor = sourceY.rounded(.down)
            let y0 = max(0, min(sourceHeight - 1, Int(yFloor)))
            let y1 = max(0, min(sourceHeight - 1, y0 + 1))
            let fy = max(0, min(1, sourceY - yFloor))
            for x in 0..<destinationWidth {
                let sourceX = (Float(x) + 0.5) * Float(sourceWidth) / Float(destinationWidth) - 0.5
                let xFloor = sourceX.rounded(.down)
                let x0 = max(0, min(sourceWidth - 1, Int(xFloor)))
                let x1 = max(0, min(sourceWidth - 1, x0 + 1))
                let fx = max(0, min(1, sourceX - xFloor))
                func alpha(_ sx: Int, _ sy: Int) -> Float {
                    Float(data[(sy * sourceWidth + sx) * 4 + 3])
                }
                let top = alpha(x0, y0) * (1 - fx) + alpha(x1, y0) * fx
                let bottom = alpha(x0, y1) * (1 - fx) + alpha(x1, y1) * fx
                let coverage = UInt32((top * (1 - fy) + bottom * fy).rounded())
                let index = (y * destinationWidth + x) * 4
                tinted[index] = red
                tinted[index + 1] = green
                tinted[index + 2] = blue
                tinted[index + 3] = UInt8((coverage * tintAlpha + 127) / 255)
            }
        }
        let handle = try bridge.registerImage(width: targetWidth, height: targetHeight, rgba: tinted, stride: targetWidth * 4)
        handles[key] = handle
        print("FACTORY_SYSTEM_IMAGE identity=star.fill provider=Segoe_Fluent_Icons glyph=E735 mappingVersion=segoe-fluent-icons-star-fill-v1 sourceRGBAsha256=\(actualHash) sourceSize=\(width)x\(height) targetSize=\(targetWidth)x\(targetHeight) tintRGBA=\(String(format: "%08x", tint)) registration=abi-0.6")
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
          node.pixelFrame.width > 0, node.pixelFrame.height > 0 else {
        throw NSError(domain: "FactorySystemImageContractMismatch", code: 1)
    }
    let tint = try factoryResolvedFill(node.style.foreground ?? .semantic("system.yellow"), opacity: node.opacity)
    let targetWidth = UInt32(max(1, Int(node.pixelFrame.width.rounded())))
    let targetHeight = UInt32(max(1, Int(node.pixelFrame.height.rounded())))
    let handle = try registry.handle(for: reference, tint: tint, width: targetWidth, height: targetHeight)
    print("FACTORY_SYSTEM_IMAGE_FRAME identity=star.fill widthPX=\(node.pixelFrame.width) heightPX=\(node.pixelFrame.height) tintRGBA=\(String(format: "%08x", tint))")
    return .image(handle, Rect(x: Float(node.pixelFrame.x), y: Float(node.pixelFrame.y),
                                w: Float(node.pixelFrame.width), h: Float(node.pixelFrame.height)))
}
