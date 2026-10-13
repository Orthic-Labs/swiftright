import Foundation
import SwiftRightRuntime
import XCTest

// SwiftUI snaps an edge at x points to pixel boundary floor((x + pixelLength / 2) / pixelLength) with pixelLength = 1 / scale in Double.
// The expectations below are MEASURED on macOS 27 (ImageRenderer, and NSHostingView.cacheDisplay, scale = capture scale), not derived from
// the rule: each probe renders a filled Color whose left edge sits at an exact half device pixel and records which pixel the edge fell on.
@MainActor
final class DevicePixelSnapTests: XCTestCase {
    /// Measured tie sweep: character n is the outcome for an edge exactly at (n + 0.5) / scale points, the Double nearest that quotient.
    /// "U" = the edge landed on pixel n + 1 (rounded up), "d" = on pixel n (rounded down).
    static let measured: [(scale: Double, outcomes: String)] = [
        (2.5, "UUddUUUUUUUdUUUUUUUUddddUddddUdddUUdddUUdUddUdUddUdUddUdUddUdUddUdUUdUdUUdUdUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddU"),
        (5.0, "UUddUUUUUUUdUUUUUUUUddddUddddUdddUUdddUUdUddUdUddUdUddUdUddUdUddUdUUdUdUUdUdUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddU"),
        (1.25, "UUddUUUUUUUdUUUUUUUUddddUddddUdddUUdddUUdUddUdUddUdUddUdUddUdUddUdUUdUdUUdUdUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddUddddU"),
        (3.0, "UUUUUUdUUUUUUUUUUUUUUUUUdUUdUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUdUUdUUdUUdUUdUUdUUdUUdUUdUUdUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUdUUdUUdUUdUUdUUd"),
        (1.5, "UUUUUUdUUUUUUUUUUUUUUUUUdUUdUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUdUUdUUdUUdUUdUUdUUdUUdUUdUUdUUdUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUUdUUdUUdUUdUUdUUd"),   // scales 3 and 1.5 are one family (the reciprocal's mantissa is identical): the sweep was run at both
    ]

    func testEveryMeasuredHalfPixelTieLandsWhereSwiftUIPutIt() {
        for (scale, outcomes) in Self.measured {
            for (n, outcome) in outcomes.enumerated() {
                let x = (Double(n) + 0.5) / scale
                let pixel = DevicePixelSnap.pixel(x, scale: scale)
                XCTAssertEqual(pixel, outcome == "U" ? Double(n + 1) : Double(n), "scale \(scale) tie at pixel \(n) + 0.5 (x = \(x) pt)")
            }
        }
    }

    /// Measured at scale 2.5 for every odd whole number of points up to 799 (the edge is 2.5 p px, an exact half pixel):
    /// 1 pt down, 3-7 up, 9-25 down, 27-127 up, 129-409 down, 411 and beyond up.
    func testScale2_5WholePointTiesFollowTheMeasuredRuns() {
        for p in stride(from: 1, to: 800, by: 2) {
            let down = p == 1 || (9...25).contains(p) || (129...409).contains(p)
            let n = (5 * Double(p) - 1) / 2
            XCTAssertEqual(DevicePixelSnap.pixel(Double(p), scale: 2.5), down ? n : n + 1, "\(p) pt")
        }
    }

    /// Away from ties it is plain nearest-pixel rounding, and scale 1, 2 and 4 (exact reciprocals) always round a tie up.
    func testNonTiesRoundToNearestAndExactScalesRoundTiesUp() {
        XCTAssertEqual(DevicePixelSnap.pixel(137.3, scale: 2.5), 343)   // 343.25 px
        XCTAssertEqual(DevicePixelSnap.pixel(137.5, scale: 2.5), 344)   // 343.75 px
        XCTAssertEqual(DevicePixelSnap.pixel(0, scale: 2.5), 0)
        for scale in [1.0, 2.0, 4.0] {
            for n in 0..<200 { XCTAssertEqual(DevicePixelSnap.pixel((Double(n) + 0.5) / scale, scale: scale), Double(n + 1), "scale \(scale) tie \(n)") }
        }
        XCTAssertEqual(DevicePixelSnap.point(25, scale: 2.5), 62 / 2.5)    // the 25 pt tie rounds down, to 62 px
        XCTAssertEqual(DevicePixelSnap.point(27, scale: 2.5), 68 / 2.5)    // the 27 pt tie rounds up, to 68 px
    }

    /// The layout engine snaps absolute edges (origin plus offsets), each edge on its own: a frame whose left edge is on a tie lands on the
    /// measured side, and the frame ends where its own far edge lands.
    func testLayoutSnapsTiesLikeSwiftUI() throws {
        struct Strip: View {
            let lead: CGFloat, width: CGFloat
            var body: some View {
                HStack(spacing: 0) {
                    Color.blue.frame(width: lead, height: 4)
                    Color.red.frame(width: width, height: 4)
                }
            }
        }
        // (lead pt, width pt, measured left px, measured right px): both edges are odd whole points, so both sit on exact half pixels
        let cases: [(lead: CGFloat, width: CGFloat, x: Int, right: Int)] = [
            (1, 20, 2, 52),
            (3, 20, 8, 57),
            (5, 20, 13, 62),
            (7, 20, 18, 68),
            (9, 20, 22, 73),
            (25, 20, 62, 113),
            (27, 20, 68, 118),
            (129, 20, 322, 372),
            (411, 20, 1028, 1078),
        ]
        for c in cases {
            let graph = Graph(Strip(lead: c.lead, width: c.width), scale: 2.5)
            graph.flush()
            let red = try node(graph.snapshot(), 0, 1)
            let left = DevicePixelSnap.pixel(Double(c.lead), scale: 2.5), right = DevicePixelSnap.pixel(Double(c.lead + c.width), scale: 2.5)
            XCTAssertEqual(red.pixelFrame.x, Int(left), "left edge of a frame at \(c.lead) pt")
            XCTAssertEqual(red.pixelFrame.x + red.pixelFrame.width, Int(right), "right edge of a frame ending at \(c.lead + c.width) pt")
            XCTAssertEqual(red.pixelFrame.x, c.x, "left edge px at \(c.lead) pt")
            XCTAssertEqual(red.pixelFrame.x + red.pixelFrame.width, c.right, "right edge px at \(c.lead + c.width) pt")
        }
    }
}
