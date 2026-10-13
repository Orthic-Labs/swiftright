import Foundation

/// SwiftUI draws a view's frame on whole device pixels: the near and far edge of a shape's frame are each
/// rounded to the nearest pixel before the path is built (measured with `ImageRenderer` at scale 2.5: a
/// 112.5 x 62.5 px frame at 343.75, 268.75 renders as 344...456 x 269...331, so a 5 px stroke has 0.5
/// coverage on both sides of every edge). The rectangle is therefore the snapped one, never the fractional
/// layout rectangle. Exact .5 ties follow the observed Mac results: the near edge rounds to even and the far
/// edge rounds half down (362.5 -> 362 and 437.5 -> 437; 237.5 -> 238 and 362.5 -> 362).
public enum DevicePixelSnap {
    /// Snaps the interval [origin, origin + length) to device pixels; returns the new origin and length.
    public static func edges(origin: Double, length: Double) -> (origin: Double, length: Double) {
        let near = origin.rounded(.toNearestOrEven)
        let end = origin + length
        let floorEnd = end.rounded(.down)
        let far = end - floorEnd > 0.5 ? floorEnd + 1 : floorEnd
        return (near, max(0, far - near))
    }
}
