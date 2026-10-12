/// Deterministic 4x4 RGBA source asset. Bytes are source evidence, not SF Symbol output.
enum FactoryRGBAAsset {
    static let name = "factory.rgba.square.v1"
    static let sourceWidth = 4
    static let sourceHeight = 4
    static let targetWidth = 32
    static let targetHeight = 32
    // 2x2 colour quadrants: red, yellow, blue, green. RGBA, row-major, 64 bytes.
    static let sourceRGBA: [UInt8] = [
        255,0,0,255, 255,0,0,255, 255,255,0,255, 255,255,0,255,
        255,0,0,255, 255,0,0,255, 255,255,0,255, 255,255,0,255,
        0,0,255,255, 0,0,255,255, 0,255,0,255, 0,255,0,255,
        0,0,255,255, 0,0,255,255, 0,255,0,255, 0,255,0,255
    ]

    /// Nearest-neighbour expansion makes backend draw rect equal target pixels,
    /// so no undocumented renderer sampling filter is admitted.
    static func nearestUpsampledRGBA() -> [UInt8] {
        var output: [UInt8] = []; output.reserveCapacity(targetWidth * targetHeight * 4)
        for y in 0..<targetHeight {
            let sy = y * sourceHeight / targetHeight
            for x in 0..<targetWidth {
                let sx = x * sourceWidth / targetWidth
                let offset = (sy * sourceWidth + sx) * 4
                output.append(contentsOf: sourceRGBA[offset..<(offset + 4)])
            }
        }
        return output
    }
}
