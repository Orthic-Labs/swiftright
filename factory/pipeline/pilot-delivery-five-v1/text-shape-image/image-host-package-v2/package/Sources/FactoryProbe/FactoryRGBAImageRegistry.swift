import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Host adapter for explicit named RGBA asset. Exact bytes are source-bound; no
/// platform catalogue or SF Symbol lookup is performed.
@MainActor final class FactoryRGBAImageRegistry {
    private let bridge: Bridge
    private var handles: [String: ImageHandle] = [:]

    init(_ bridge: Bridge) { self.bridge = bridge }

    func handle(for reference: ImageReference) throws -> ImageHandle {
        guard case .named(let name) = reference, name == FactoryRGBAAsset.name else {
            throw NSError(domain: "FactoryImageAssetProviderMissing", code: 1)
        }
        if let cached = handles[name] { return cached }
        let pixels = FactoryRGBAAsset.bilinearUpsampledRGBA()
        print("FACTORY_IMAGE_ASSET name=\(name) source=\(FactoryRGBAAsset.sourceWidth)x\(FactoryRGBAAsset.sourceHeight) target=\(FactoryRGBAAsset.targetWidth)x\(FactoryRGBAAsset.targetHeight) sampling=\(FactoryRGBAAsset.samplingMode) rawRGBAHash=\(FactoryRGBAAsset.sourceRGBASHA256)")
        let handle = try bridge.registerImage(
            width: UInt32(FactoryRGBAAsset.targetWidth),
            height: UInt32(FactoryRGBAAsset.targetHeight),
            rgba: pixels,
            stride: UInt32(FactoryRGBAAsset.targetWidth * 4)
        )
        handles[name] = handle
        return handle
    }

    func releaseAll() {
        for handle in handles.values { _ = bridge.release(handle) }
        handles.removeAll(keepingCapacity: false)
    }
}

/// Branch body for existing `ResolvedNode` walk.
@MainActor func factoryRGBAImagePrimitive(
    _ node: ResolvedNode,
    registry: FactoryRGBAImageRegistry
) throws -> Primitive {
    guard node.kind == "Image", let reference = node.image,
          let sizing = node.imageSizing,
          sizing.isResizable, sizing.scalesToFit,
          node.opacity == 1 else {
        throw NSError(domain: "FactoryImageContractMismatch", code: 1)
    }
    guard node.frame.width == CGFloat(FactoryRGBAAsset.targetWidth),
          node.frame.height == CGFloat(FactoryRGBAAsset.targetHeight),
          node.pixelFrame.width > 0, node.pixelFrame.height > 0 else {
        throw NSError(domain: "FactoryImageFrameMismatch", code: 1)
    }
    let handle = try registry.handle(for: reference)
    return .image(handle, Rect(
        x: Float(node.pixelFrame.x), y: Float(node.pixelFrame.y),
        w: Float(node.pixelFrame.width), h: Float(node.pixelFrame.height)
    ))
}
