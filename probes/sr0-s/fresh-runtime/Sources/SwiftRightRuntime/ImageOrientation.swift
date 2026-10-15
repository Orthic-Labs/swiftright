import Foundation

// Wave 0 block I1: image orientation (EXIF 1-8) as pure pixel moves, shared by the decode service (EXIF applied at decode) and `Image(decorative:scale:orientation:)`.

extension Image {
    /// Apple: https://developer.apple.com/documentation/swiftui/image/orientation
    /// The eight cases follow EXIF order: `up` = 1, `upMirrored` = 2, `down` = 3, `downMirrored` = 4, `leftMirrored` = 5, `right` = 6, `rightMirrored` = 7, `left` = 8
    /// (EXIF value N means: apply this to the stored pixels to display them upright; `right` rotates 90 degrees clockwise).
    public enum Orientation: UInt8, CaseIterable, Hashable, Sendable {
        case up, upMirrored, down, downMirrored, leftMirrored, right, rightMirrored, left

        /// EXIF / TIFF orientation value 1...8.
        public var exif: Int { Int(rawValue) + 1 }
        /// nil outside 1...8.
        public init?(exif: Int) { guard (1...8).contains(exif) else { return nil }; self.init(rawValue: UInt8(exif - 1)) }
    }
}

extension RGBAImage {
    /// The image with an EXIF orientation applied (1 = unchanged; 5...8 swap width and height). Pure index arithmetic: exact, no resampling.
    public func oriented(exif value: Int) -> RGBAImage {
        guard (2...8).contains(value) else { return self }
        let sw = width, sh = height, swap = value >= 5
        let dw = swap ? sh : sw, dh = swap ? sw : sh
        var out = [UInt8](repeating: 0, count: dw * dh * 4)
        rgba.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<dh {
                    for x in 0..<dw {
                        let sx: Int, sy: Int
                        switch value {
                        case 2: sx = sw - 1 - x; sy = y
                        case 3: sx = sw - 1 - x; sy = sh - 1 - y
                        case 4: sx = x; sy = sh - 1 - y
                        case 5: sx = y; sy = x
                        case 6: sx = y; sy = sh - 1 - x
                        case 7: sx = sw - 1 - y; sy = sh - 1 - x
                        default: sx = sw - 1 - y; sy = x
                        }
                        let s = (sy * sw + sx) * 4, d = (y * dw + x) * 4
                        dst[d] = src[s]; dst[d + 1] = src[s + 1]; dst[d + 2] = src[s + 2]; dst[d + 3] = src[s + 3]
                    }
                }
            }
        }
        return RGBAImage(width: dw, height: dh, rgba: out)!
    }

    public func oriented(_ orientation: Image.Orientation) -> RGBAImage { oriented(exif: orientation.exif) }
}
