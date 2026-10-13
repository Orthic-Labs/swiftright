import SwiftRightRuntime
import SwiftRightBridge

// Exact source-owned 2x2 RGBA8 asset. No SF Symbol or platform catalogue mapping.
// Row-major straight-alpha bytes: red, green, blue, white.
@MainActor final class FactoryImageAssetStore {
    static let name = "sr1.rgba.checker"
    static let width: UInt32 = 2
    static let height: UInt32 = 2
    static let rgba: [UInt8] = [
        255, 0, 0, 255,  0, 255, 0, 255,
        0, 0, 255, 255,  255, 255, 255, 255
    ]
    static let rgbaSha256 = "c21b35e3f28e676cedf24c13575a7346682e101a2d26aad9598d0cdbcee9ee3b"

    let bridge: Bridge
    private var handles: [ImageReference: ImageHandle] = [:]
    init(_ bridge: Bridge) { self.bridge = bridge }

    func handle(for reference: ImageReference) throws -> ImageHandle {
        guard case .named(Self.name) = reference else {
            throw NSError(domain: "FactoryImageAssetOnly", code: 1)
        }
        if let existing = handles[reference] { return existing }
        guard handles.count < 8 else {
            throw NSError(domain: "FactoryImageAssetHandleBound", code: 1)
        }
        let handle = try bridge.registerImage(width: Self.width, height: Self.height, rgba: Self.rgba)
        handles[reference] = handle
        return handle
    }

    func releaseAll() {
        handles.values.forEach { _ = bridge.release($0) }
        handles.removeAll()
    }
}
