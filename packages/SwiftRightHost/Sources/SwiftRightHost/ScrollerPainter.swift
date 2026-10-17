import Foundation
import SwiftRightRuntime
import SwiftRightBridge

/// Colours of the legacy vertical scroller, 0xRRGGBB, painted opaque.
public enum ScrollerColors {
    // TO MEASURE (M5, #31)
    public static let track: UInt32 = 0xfafafa
    // TO MEASURE (M5, #31)
    public static let trackBorder: UInt32 = 0xebebeb
    // TO MEASURE (M5, #31)
    public static let thumb: UInt32 = 0xc2c2c2
}

/// Where a legacy vertical scroller is drawn, in window pixels: the strip at the container's trailing edge and the thumb inside it.
public struct ScrollerLayout: Equatable {
    public var strip: Rect
    public var thumb: Rect
}

/// The legacy vertical scroller of a List or ScrollView (AppKit's `NSScroller` in the legacy style, measured constants in `ScrollerMetrics`).
/// The strip is `ScrollerMetrics.width` points wide at the trailing edge of the container's frame, the full frame height. The thumb sits inside it:
/// the track is the viewport less the top and bottom insets, the thumb is `max(minThumbLength, track * viewport / content)` long (never longer than the
/// track), and its top is `thumbInsetTop + (track - thumb) * value`. Edges snap to whole device pixels.
public enum ScrollerPainter {
    /// The thumb's top and length in points, measured from the top of the container's frame. nil when the scroller is not shown.
    public static func thumbPoints(for scroll: ScrollState) -> (top: Double, length: Double)? {
        guard scroll.showsScroller, scroll.maxOffset > 0, scroll.viewportHeight > 0 else { return nil }
        let viewport = scroll.viewportHeight
        let insetTop = Double(ScrollerMetrics.thumbInsetTop), insetBottom = Double(ScrollerMetrics.thumbInsetBottom)
        let track = max(0, viewport - insetTop - insetBottom)
        let proportional = track * viewport / scroll.contentHeight
        // The minimum length wins over the proportion, but a thumb cannot be longer than its track (a track shorter than the minimum).
        let length = min(track, max(Double(ScrollerMetrics.minThumbLength), proportional))
        let value = min(1, max(0, scroll.value))
        return (insetTop + (track - length) * value, length)
    }

    /// The strip and the thumb for a container whose frame is `frame` (window pixels) at `scale`. nil when the scroller is not shown.
    public static func layout(frame: Rect, scale: Float, scroll: ScrollState) -> ScrollerLayout? {
        guard let thumb = thumbPoints(for: scroll) else { return nil }
        let s = Double(scale)
        let frameTop = Double(frame.y), frameBottom = Double(frame.y) + Double(frame.h)
        let frameRight = Double(frame.x) + Double(frame.w)
        let stripLeft = frameRight - Double(ScrollerMetrics.width) * s
        let strip = pixelRect(x0: stripLeft, x1: frameRight, y0: frameTop, y1: frameBottom)
        let thumbLeft = stripLeft + Double(ScrollerMetrics.thumbInsetLeading) * s
        let thumbRight = thumbLeft + Double(ScrollerMetrics.thumbWidth) * s
        let thumbRect = pixelRect(x0: thumbLeft, x1: thumbRight,
                                  y0: frameTop + thumb.top * s, y1: frameTop + (thumb.top + thumb.length) * s)
        return ScrollerLayout(strip: strip, thumb: thumbRect)
    }

    /// The paint of a layout: the track fill, a one-point border on its leading edge, and the rounded thumb (radius half its width).
    public static func primitives(for layout: ScrollerLayout, scale: Float) -> [Primitive] {
        let strip = layout.strip, thumb = layout.thumb
        let borderWidth = max(1, scale.rounded(.toNearestOrAwayFromZero))   // 1 pt in device pixels, whole
        return [
            .rect(strip, color: opaque(ScrollerColors.track)),
            .rect(Rect(x: strip.x, y: strip.y, w: borderWidth, h: strip.h), color: opaque(ScrollerColors.trackBorder)),
            .rect(thumb, color: opaque(ScrollerColors.thumb), radius: thumb.w / 2),
        ]
    }

    /// A `Rect` as a `CGRect` (the same window-pixel space).
    public static func cgRect(_ r: Rect) -> CGRect { CGRect(x: CGFloat(r.x), y: CGFloat(r.y), width: CGFloat(r.w), height: CGFloat(r.h)) }

    static func opaque(_ rgb: UInt32) -> UInt32 { rgb << 8 | 0xff }

    static func pixelRect(x0: Double, x1: Double, y0: Double, y1: Double) -> Rect {
        let left = snap(x0), right = snap(x1), top = snap(y0), bottom = snap(y1)
        return Rect(x: Float(left), y: Float(top), w: Float(max(0, right - left)), h: Float(max(0, bottom - top)))
    }

    static func snap(_ v: Double) -> Double { v.rounded(.toNearestOrAwayFromZero) }
}
