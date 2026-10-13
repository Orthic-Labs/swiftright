/// Deterministic 4x4 RGBA source asset. Bytes are source evidence, not SF Symbol output.
enum FactoryRGBAAsset {
    static let name = "factory.rgba.square.v1"
    static let sourceWidth = 4
    static let sourceHeight = 4
    static let targetWidth = 32
    static let targetHeight = 32
    static let sourceRGBASHA256 = "dc3ae926d85afbeca3cc60a12a8c69faad0f0b31f60c76ebe55bf4be00aab008"
    // 2x2 colour quadrants: red, yellow, blue, green. RGBA, row-major, 64 bytes.
    static let sourceRGBA: [UInt8] = [
        255,0,0,255, 255,0,0,255, 255,255,0,255, 255,255,0,255,
        255,0,0,255, 255,0,0,255, 255,255,0,255, 255,255,0,255,
        0,0,255,255, 0,0,255,255, 0,255,0,255, 0,255,0,255,
        0,0,255,255, 0,0,255,255, 0,255,0,255, 0,255,0,255
    ]

    /// Mac Image("factory.rgba.square.v1") capture shows interpolated quadrant
    /// boundaries after 4x4 -> 32x32 scaling. Sample destination pixel centers
    /// in source space, clamp at edges, & interpolate opaque sRGB channels.
    /// This keeps sampling explicit before bridge.registerImage; renderer-side
    /// image filtering remains an independent receipt requirement.
    static let samplingMode = "bilinear-center-sampled-srgb-opaque"

    static func bilinearUpsampledRGBA() -> [UInt8] {
        var output: [UInt8] = []; output.reserveCapacity(targetWidth * targetHeight * 4)
        for y in 0..<targetHeight {
            let sourceY = min(max(((Double(y) + 0.5) * Double(sourceHeight) / Double(targetHeight)) - 0.5, 0), Double(sourceHeight - 1))
            let y0 = Int(sourceY.rounded(.down))
            let y1 = min(y0 + 1, sourceHeight - 1)
            let ty = sourceY - Double(y0)
            for x in 0..<targetWidth {
                let sourceX = min(max(((Double(x) + 0.5) * Double(sourceWidth) / Double(targetWidth)) - 0.5, 0), Double(sourceWidth - 1))
                let x0 = Int(sourceX.rounded(.down))
                let x1 = min(x0 + 1, sourceWidth - 1)
                let tx = sourceX - Double(x0)
                let top = (1 - tx, tx)
                let bottom = (1 - tx, tx)
                let offsets = [(y0 * sourceWidth + x0) * 4, (y0 * sourceWidth + x1) * 4,
                               (y1 * sourceWidth + x0) * 4, (y1 * sourceWidth + x1) * 4]
                for channel in 0..<4 {
                    let topValue = Double(sourceRGBA[offsets[0] + channel]) * top.0 + Double(sourceRGBA[offsets[1] + channel]) * top.1
                    let bottomValue = Double(sourceRGBA[offsets[2] + channel]) * bottom.0 + Double(sourceRGBA[offsets[3] + channel]) * bottom.1
                    let value = topValue * (1 - ty) + bottomValue * ty
                    output.append(UInt8(max(0, min(255, Int(value.rounded())))))
                }
            }
        }
        return output
    }
}
