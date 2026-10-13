import Foundation

/// SwiftUI draws a view's frame on whole device pixels: the near and far edge of a frame are each rounded
/// to a pixel boundary (measured with `ImageRenderer` and `NSHostingView.cacheDisplay` at scale 2.5: a
/// 112.5 x 62.5 px frame at 343.75, 268.75 renders as 344...456 x 269...331).
///
/// **Rule (measured, pixel-ties lane).** An edge at `x` points lands on pixel boundary
/// `floor((x + pixelLength / 2) / pixelLength)` where `pixelLength = 1 / scale`, every operation in `Double`
/// (`pixelLength` is the rounded reciprocal, not an exact one). It is "round half up" on paper, but because
/// the reciprocal and the quotient are rounded, an edge that lands exactly on a half pixel falls on either side
/// depending on the value: at scale 2.5, 1 pt rounds down (2.5 -> 2), 3 to 7 pt round up, 9 to 25 pt down, 27 to
/// 127 pt up, 129 to 409 pt down, 411 pt and beyond up. Fitted on 2,400 tie probes (scales 1.25, 1.5, 2.5, 3, 5; ties
/// at whole points and at inexact points), then held out on 10,600 more (scales 0.75 to 7, ImageRenderer and
/// NSHostingView, x and y, padding/offset/overlay/stack paths, up to 7,500 px): no mismatch. Non-tie edges are plain
/// nearest-pixel (600 random edges per scale, no mismatch). Both edges of a frame use it separately; the edge is the
/// absolute position (origin plus offsets, summed in `Double`), never a position relative to the parent.
/// Limit: the input must be the same `Double` SwiftUI computed. Exact layouts (whole and dyadic points) give the same
/// sums, so ties there are reproduced; a position built by inexact arithmetic (0.1 steps, halving an inexact length)
/// carries 1-ulp noise that decides the tie, and matches only if the runtime does the same arithmetic.
public enum DevicePixelSnap {
    /// The device pixel boundary an edge at `x` points snaps to, as a pixel index (an integral `Double`).
    public static func pixel(_ x: Double, scale: Double) -> Double {
        guard x.isFinite, scale.isFinite, scale > 0 else { return x * scale }
        let pixelLength = 1 / scale
        return ((x + pixelLength / 2) / pixelLength).rounded(.down)
    }

    /// The same boundary in points (`pixel / scale`), what the layout engine stores as a snapped edge.
    public static func point(_ x: Double, scale: Double) -> Double {
        pixel(x, scale: scale) / scale
    }

    /// Snaps the interval [origin, origin + length) given in device pixels (a painter's bounds) to whole pixels at `scale`;
    /// returns the new origin and length in pixels. Each edge is snapped by `pixel(_:scale:)` as the equivalent point.
    public static func edges(origin: Double, length: Double, scale: Double = 1) -> (origin: Double, length: Double) {
        let near = pixel(origin / scale, scale: scale)
        let far = pixel((origin + length) / scale, scale: scale)
        return (near, max(0, far - near))
    }
}
