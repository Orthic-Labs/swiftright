import Foundation
import SwiftRightRuntime

/// Wave 0 block I1: ICC matrix/TRC RGB profile -> sRGB, in Swift. Why it exists: the WIC colour transform (IWICColorTransform) gamut-MAPS colours that fall outside sRGB, CoreGraphics CLIPS them
/// (measured: Display P3 (176,36,120) gives sRGB G = 0 on the Mac and G = 21 through WIC; the transform's output is identical for every rendering intent written into the profile header,
/// so the intent cannot be set to match). Matrix/TRC profiles (Display P3, Adobe RGB, camera and scanner RGB profiles, sRGB variants) are the usual embedded profiles and need no LUT, so this
/// converts them exactly the way a clipping colorimetric conversion does; a grey kTRC profile (XYZ PCS) is the same curve on all three channels; a profile with an A2B0 LUT, a Lab-PCS grey or a CMYK profile falls back to the WIC transform.
/// Maths: linearise each channel through the profile's TRC, multiply by the profile's D50 colorant matrix to XYZ(D50), by the inverse of sRGB's D50 colorant matrix to linear sRGB,
/// clip to 0...1, encode with the sRGB curve, round to nearest. Alpha is untouched (straight).
struct ICCMatrixTRC {
    private var curves: [[Double]]      // 3 x 256 linear values
    private var matrix: [Double]        // 3x3 row-major: profile RGB (linear) -> sRGB (linear)

    /// nil when the profile is not an RGB matrix/TRC profile with an XYZ PCS.
    init?(profile p: [UInt8]) {
        guard p.count >= 132 else { return nil }
        func u32(_ i: Int) -> Int { i + 4 <= p.count ? Int(p[i]) << 24 | Int(p[i + 1]) << 16 | Int(p[i + 2]) << 8 | Int(p[i + 3]) : -1 }
        func tag4(_ i: Int) -> String { i + 4 <= p.count ? String(decoding: p[i..<i + 4], as: UTF8.self) : "" }
        let isGrey = tag4(16) == "GRAY"
        guard tag4(16) == "RGB " || isGrey, tag4(20) == "XYZ " else { return nil }
        let n = u32(128)
        guard n > 0, n < 200, p.count >= 132 + n * 12 else { return nil }
        var tags: [String: (Int, Int)] = [:]
        for k in 0..<n { let e = 132 + k * 12; tags[tag4(e)] = (u32(e + 4), u32(e + 8)) }
        guard tags["A2B0"] == nil, tags["A2B1"] == nil else { return nil }
        func s15(_ i: Int) -> Double { Double(Int32(truncatingIfNeeded: u32(i))) / 65536 }
        func xyz(_ name: String) -> [Double]? {
            guard let (o, s) = tags[name], s >= 20, o >= 0, o + 20 <= p.count, tag4(o) == "XYZ " else { return nil }
            return [s15(o + 8), s15(o + 12), s15(o + 16)]
        }
        let colorants = isGrey ? nil : [xyz("rXYZ"), xyz("gXYZ"), xyz("bXYZ")]
        if !isGrey { guard colorants![0] != nil, colorants![1] != nil, colorants![2] != nil else { return nil } }
        func curve(_ name: String) -> [Double]? {
            guard let (o, s) = tags[name], s >= 12, o >= 0, o + s <= p.count else { return nil }
            var f: (Double) -> Double
            switch tag4(o) {
            case "curv":
                let count = u32(o + 8)
                guard count >= 0, o + 12 + count * 2 <= p.count else { return nil }
                if count == 0 { f = { $0 } }
                else if count == 1 { let gamma = Double(Int(p[o + 12]) << 8 | Int(p[o + 13])) / 256; f = { pow($0, gamma) } }
                else {
                    let table = (0..<count).map { Double(Int(p[o + 12 + $0 * 2]) << 8 | Int(p[o + 13 + $0 * 2])) / 65535 }
                    f = { x in
                        let pos = x * Double(count - 1), i = min(count - 2, Int(pos)), t = pos - Double(i)
                        return table[i] + (table[i + 1] - table[i]) * t
                    }
                }
            case "para":
                let type = Int(p[o + 8]) << 8 | Int(p[o + 9])
                let counts = [1, 3, 4, 5, 7]
                guard type >= 0, type < 5, o + 12 + counts[type] * 4 <= p.count else { return nil }
                let q = (0..<counts[type]).map { s15(o + 12 + $0 * 4) }
                switch type {
                case 0: f = { pow($0, q[0]) }
                case 1: f = { $0 >= -q[2] / q[1] ? pow(q[1] * $0 + q[2], q[0]) : 0 }
                case 2: f = { $0 >= -q[2] / q[1] ? pow(q[1] * $0 + q[2], q[0]) + q[3] : q[3] }
                case 3: f = { $0 >= q[4] ? pow(q[1] * $0 + q[2], q[0]) : q[3] * $0 }
                default: f = { $0 >= q[4] ? pow(q[1] * $0 + q[2], q[0]) + q[5] : q[3] * $0 + q[6] }
                }
            default: return nil
            }
            return (0..<256).map { max(0, min(1, f(Double($0) / 255))) }
        }
        if isGrey {
            // Grey profile (kTRC, XYZ PCS): Y = TRC(v), XYZ(D50) = Y x D50 white, and the D50 white maps to linear sRGB (1, 1, 1), so R = G = B = TRC(v): identity matrix on three copies of the curve.
            // Not yet measured against ImageIO (issue #61, png-icc-grey-v1 gates it on the next CI pair); the WIC colour transform rejects a grey source context for BGRA (HRESULT 0x800707DB, ERROR_INVALID_PROFILE).
            guard let k = curve("kTRC") else { return nil }
            curves = [k, k, k]
            matrix = [1, 0, 0, 0, 1, 0, 0, 0, 1]
            return
        }
        guard let cr = curve("rTRC"), let cg = curve("gTRC"), let cb = curve("bTRC") else { return nil }
        curves = [cr, cg, cb]
        let r = colorants![0]!, g = colorants![1]!, b = colorants![2]!
        // profile RGB -> XYZ(D50): columns are the colorants; sRGB (D50, Bradford) colorants as in the ICC sRGB profile
        let toXYZ = [r[0], g[0], b[0], r[1], g[1], b[1], r[2], g[2], b[2]]
        let srgb: [Double] = [0.4360747, 0.3850649, 0.1430804, 0.2225045, 0.7168786, 0.0606169, 0.0139322, 0.0971045, 0.7141733]
        guard let inverse = Self.invert(srgb) else { return nil }
        matrix = Self.multiply(inverse, toXYZ)
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var c = [Double](repeating: 0, count: 9)
        for i in 0..<3 { for j in 0..<3 { for k in 0..<3 { c[i * 3 + j] += a[i * 3 + k] * b[k * 3 + j] } } }
        return c
    }

    private static func invert(_ m: [Double]) -> [Double]? {
        let (a, b, c, d, e, f, g, h, i) = (m[0], m[1], m[2], m[3], m[4], m[5], m[6], m[7], m[8])
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        guard abs(det) > 1e-12 else { return nil }
        return [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
                (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
                (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]
    }

    @inline(__always) private static func encode(_ l: Double) -> UInt8 {
        let v = max(0, min(1, l))
        let e = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (e * 255).rounded())))
    }

    /// Converts the colour of every pixel; alpha is copied.
    func toSRGB(_ image: RGBAImage) -> RGBAImage {
        var out = image.rgba
        let m = matrix
        out.withUnsafeMutableBufferPointer { px in
            var i = 0
            while i < px.count {
                let r = curves[0][Int(px[i])], g = curves[1][Int(px[i + 1])], b = curves[2][Int(px[i + 2])]
                px[i] = Self.encode(m[0] * r + m[1] * g + m[2] * b)
                px[i + 1] = Self.encode(m[3] * r + m[4] * g + m[5] * b)
                px[i + 2] = Self.encode(m[6] * r + m[7] * g + m[8] * b)
                i += 4
            }
        }
        return RGBAImage(width: image.width, height: image.height, rgba: out)!
    }
}
