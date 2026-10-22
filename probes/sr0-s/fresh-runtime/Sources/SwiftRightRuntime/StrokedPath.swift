import Foundation

// Issue #84 (SR2 S4): Path.strokedPath(_:). The outline is the union of the stroke's pieces as the rasterizer builds them (one quadrilateral per
// segment, round joins and caps as discs, miter wedges), flattened to polygons and written with one winding direction so that filling the result with the non-zero rule gives the
// stroke. It is not a merged outline: overlapping pieces stay separate subpaths (fill it, or clip with it; do not stroke it or measure its length).

extension Path {
    /// Apple: https://developer.apple.com/documentation/swiftui/path/strokedpath(_:)
    public func strokedPath(_ style: StrokeStyle) -> Path {
        let subpaths = PathSegments.subpaths(of: self)
        guard !subpaths.isEmpty, style.lineWidth > 0 else { return Path() }
        let matrix = PathRasterizer.Matrix(transform: .identity, scale: 1)
        let polys = subpaths.map { PathRasterizer.flatten($0, matrix, tolerance: 0.05) }
        let lengths: [Double]? = style.dash.isEmpty ? nil : subpaths.map { $0.segments.reduce(0.0) { $0 + $1.length() } }
        guard let pieces = try? PathRasterizer.strokePieces(polys, style: style, lengthScale: 1, trueLengths: lengths) else { return Path() }
        var out = Path()
        for piece in pieces {
            if piece.isDisc {
                out.addEllipse(in: CGRect(x: piece.cx - piece.r, y: piece.cy - piece.r, width: 2 * piece.r, height: 2 * piece.r))
                continue
            }
            var points = zip(piece.vx, piece.vy).map { CGPoint(x: $0, y: $1) }
            if piece.orient < 0 { points.reverse() }
            out.addLines(points)
            out.closeSubpath()
        }
        return out
    }
}
