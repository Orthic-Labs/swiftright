import Foundation
import SwiftRightRuntime
import XCTest

/// F-path (#35): `.rotationEffect(_:anchor:)` changes no layout and only records the angle and anchor for the host.
@MainActor
final class RotationEffectTests: XCTestCase {
    private func nodes<V: View>(_ view: V, w: CGFloat = 200, h: CGFloat = 100) throws -> [ResolvedNode] {
        let graph = Graph(view, scale: 2)
        graph.rootProposal = ProposedViewSize(width: w, height: h)
        graph.flush()
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return walk(try XCTUnwrap(graph.snapshot()))
    }

    private func row(rotated: Bool) -> some View {
        HStack(spacing: 8) {
            if rotated {
                Color.red.frame(width: 40, height: 20).rotationEffect(.degrees(30), anchor: .topLeading)
            } else {
                Color.red.frame(width: 40, height: 20)
            }
            Color.blue.frame(width: 10, height: 10)
        }
    }

    func testRotationDoesNotChangeLayout() throws {
        let plain = try nodes(row(rotated: false)).filter { $0.kind == "Color" }
        let rotated = try nodes(row(rotated: true)).filter { $0.kind == "Color" }
        XCTAssertEqual(plain.count, 2)
        XCTAssertEqual(rotated.map(\.frame), plain.map(\.frame), "frames, hence sizes and positions, are those of the unrotated view")
        XCTAssertEqual(rotated.map(\.pixelFrame), plain.map(\.pixelFrame))
        let modifier = try XCTUnwrap(try nodes(row(rotated: true)).first { $0.kind == "modifier.rotationEffect" })
        XCTAssertEqual(modifier.frame, try XCTUnwrap(rotated.first).frame, "the modifier node has its child's frame")
    }

    func testAngleAndAnchorAreRecordedOnTheModifierNode() throws {
        let all = try nodes(Color.red.frame(width: 40, height: 20).rotationEffect(.radians(1.25), anchor: .bottomTrailing))
        let modifier = try XCTUnwrap(all.first { $0.kind == "modifier.rotationEffect" })
        XCTAssertEqual(modifier.rotation, ResolvedRotation(angle: .radians(1.25), anchor: .bottomTrailing))
        XCTAssertNil(all.first { $0.kind == "Color" }?.rotation, "only the modifier node carries it")
    }

    func testTheDefaultAnchorIsTheCenter() throws {
        let modifier = try XCTUnwrap(try nodes(Color.red.frame(width: 40, height: 20).rotationEffect(.degrees(90))).first { $0.kind == "modifier.rotationEffect" })
        XCTAssertEqual(modifier.rotation?.anchor, .center)
        XCTAssertEqual(try XCTUnwrap(modifier.rotation).angle.degrees, 90, accuracy: 1e-9)
    }

    func testNestedRotationsAreListedOutermostFirstAndEachKeepsItsOwnAnchor() throws {
        let all = try nodes(Color.red.frame(width: 40, height: 20)
            .rotationEffect(.radians(0.5), anchor: .topLeading)
            .rotationEffect(.radians(2), anchor: .bottom))
        let modifiers = all.filter { $0.kind == "modifier.rotationEffect" }
        XCTAssertEqual(modifiers.compactMap(\.rotation), [ResolvedRotation(angle: .radians(2), anchor: .bottom),
                                                          ResolvedRotation(angle: .radians(0.5), anchor: .topLeading)])
        XCTAssertEqual(modifiers.map(\.frame).first, modifiers.map(\.frame).last)
    }

    func testRotationDoesNotChangeTheSizeTheParentSees() throws {
        // a 40 x 20 view rotated by 90 degrees still takes 40 x 20 in a centred stack
        let frames = try nodes(HStack(spacing: 0) { Color.red.frame(width: 40, height: 20).rotationEffect(.degrees(90)); Color.blue.frame(width: 10, height: 10) }).filter { $0.kind == "Color" }.map(\.frame)
        XCTAssertEqual(frames[0].width, 40); XCTAssertEqual(frames[0].height, 20)
        XCTAssertEqual(frames[1].minX, frames[0].minX + 40)
    }
}
