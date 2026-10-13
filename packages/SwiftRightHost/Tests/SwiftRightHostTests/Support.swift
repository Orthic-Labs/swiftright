import Foundation
import SwiftRightHost

/// Records registered images; no renderer.
final class FakeImages: ImageRegistering {
    struct Entry { var width: UInt32; var height: UInt32; var rgba: [UInt8] }
    private(set) var registered: [UInt64: Entry] = [:]
    private(set) var released: [UInt64] = []
    private var next: UInt64 = 1
    func registerImage(width: UInt32, height: UInt32, rgba: [UInt8], stride: UInt32) throws -> ImageHandle {
        defer { next += 1 }
        registered[next] = Entry(width: width, height: height, rgba: rgba)
        return ImageHandle(raw: next)
    }
    @discardableResult func release(_ image: ImageHandle) -> Bool { released.append(image.raw); return true }
    var live: Set<UInt64> { Set(registered.keys).subtracting(released) }
}

/// A solid rectangle of coverage at the requested size (what a symbol outline would give), recording each request.
final class FakeGlyphs: SystemGlyphRasterizing {
    private(set) var requests: [(family: String, glyph: UInt32, w: UInt32, h: UInt32)] = []
    var face: String?
    func rasterize(providerFamily: String, glyph: UInt32, targetWidth: UInt32, targetHeight: UInt32) throws -> SystemGlyphCoverage {
        requests.append((providerFamily, glyph, targetWidth, targetHeight))
        let w = Int(targetWidth), h = Int(targetHeight)
        var c = [UInt8](repeating: 0, count: w * h)
        for y in h / 8..<(h - h / 8) { for x in w / 8..<(w - w / 8) { c[y * w + x] = 64 } }
        return SystemGlyphCoverage(sourceWidth: targetWidth, sourceHeight: targetHeight, rowBytes: targetWidth, coverage: c,
                                   coverageMaximum: 64, rowOrder: .topDown, selectedFace: face ?? providerFamily)
    }
}

func flatten(_ node: ResolvedNode) -> [ResolvedNode] { [node] + node.children.flatMap(flatten) }
