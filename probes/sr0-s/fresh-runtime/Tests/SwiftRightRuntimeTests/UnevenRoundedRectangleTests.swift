import SwiftRightRuntime
import XCTest

final class UnevenRoundedRectangleTests: XCTestCase {
    private let rect = CGRect(x: 10, y: 20, width: 100, height: 60)

    private func describe(_ p: Path) -> [String] {
        func f(_ q: CGPoint) -> String { String(format: "%.3f,%.3f", Double(q.x), Double(q.y)) }
        return p.elements.map { e in
            switch e {
            case .move(let a): return "m " + f(a)
            case .line(let a): return "l " + f(a)
            case .quadCurve(let a, let c): return "q " + f(a) + " " + f(c)
            case .curve(let a, let c1, let c2): return "c " + f(a) + " " + f(c1) + " " + f(c2)
            case .closeSubpath: return "z"
            }
        }
    }
    private func endpoints(_ p: Path) -> [CGPoint] {
        p.elements.compactMap { e in
            switch e { case .move(let a), .line(let a): return a; case .quadCurve(let a, _), .curve(let a, _, _): return a; case .closeSubpath: return nil }
        }
    }

    func testEqualRadiiMatchRoundedRectangleContinuous() {
        let uneven = UnevenRoundedRectangle(cornerRadii: .init(topLeading: 14, bottomLeading: 14, bottomTrailing: 14, topTrailing: 14)).path(in: rect)
        let rounded = RoundedRectangle(cornerRadius: 14, style: .continuous).path(in: rect)
        XCTAssertEqual(uneven.boundingRect, rounded.boundingRect)
        XCTAssertEqual(describe(uneven), describe(rounded))
    }

    func testZeroRadiiIsTheRectangle() {
        let p = UnevenRoundedRectangle(cornerRadii: .init()).path(in: rect)
        XCTAssertEqual(p.boundingRect, rect)
    }

    func testOneRoundedCornerLeavesTheOthersSquare() {
        let p = UnevenRoundedRectangle(topLeadingRadius: 20).path(in: rect)
        XCTAssertEqual(p.boundingRect, rect)
        let pts = endpoints(p)
        XCTAssertFalse(pts.contains(CGPoint(x: 10, y: 20)), "the rounded top-leading corner never reaches its vertex")
        XCTAssertTrue(pts.contains(CGPoint(x: 110, y: 80)), "the square bottom-trailing corner is a vertex")
        XCTAssertTrue(pts.contains(CGPoint(x: 110, y: 20)) && pts.contains(CGPoint(x: 10, y: 80)))
    }

    func testRadiiThatDoNotFitShrink() {
        let p = UnevenRoundedRectangle(topLeadingRadius: 60, bottomLeadingRadius: 60, bottomTrailingRadius: 60, topTrailingRadius: 60).path(in: rect)
        XCTAssertEqual(p.boundingRect, rect)
    }
}
