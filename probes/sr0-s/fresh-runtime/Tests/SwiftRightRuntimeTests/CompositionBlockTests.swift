import Foundation
import SwiftRightRuntime
import XCTest

/// SR2 block R1 (#36): Group, ViewModifier, background, offset, position, GeometryReader, allowsHitTesting. Sizes and positions are in points, against the documented SwiftUI
/// behaviour (the Mac oracle cases are the lead's next step); scale 1 keeps frames unsnapped.
@MainActor
final class CompositionBlockTests: XCTestCase {
    private func graph<V: View>(_ view: V, w: CGFloat? = 300, h: CGFloat? = 200) -> Graph {
        let g = Graph(view, scale: 1)
        g.rootProposal = ProposedViewSize(width: w, height: h)
        g.flush()
        return g
    }

    private func nodes<V: View>(_ view: V, w: CGFloat? = 300, h: CGFloat? = 200) throws -> [ResolvedNode] {
        let g = graph(view, w: w, h: h)
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return walk(try XCTUnwrap(g.snapshot()))
    }

    private func frame(_ n: ResolvedNode) -> [CGFloat] { [n.frame.minX, n.frame.minY, n.frame.width, n.frame.height] }

    // MARK: Group

    func testGroupMembersAreLaidOutByTheParentStack() throws {
        let all = try nodes(VStack(spacing: 10) {
            Group {
                Color.red.frame(width: 50, height: 20)
                Color.blue.frame(width: 50, height: 20)
            }
            Color.green.frame(width: 50, height: 20)
        })
        let colors = all.filter { $0.kind == "Color" }
        XCTAssertEqual(colors.map(\.frame.minY), [0, 30, 60], "three children spaced by the VStack: the Group adds no layer and no spacing of its own")
        XCTAssertEqual(all.first?.frame.height, 80)
        XCTAssertEqual(all.filter { $0.kind == "Group" }.count, 0, "a Group is not a node")
    }

    func testGroupInAnHStackRunsAlongTheRow() throws {
        let colors = try nodes(HStack(spacing: 4) {
            Group { Color.red.frame(width: 10, height: 10); Color.blue.frame(width: 10, height: 10) }
            Color.green.frame(width: 10, height: 10)
        }).filter { $0.kind == "Color" }
        XCTAssertEqual(colors.map(\.frame.minX), [0, 14, 28])
    }

    func testAModifierOnAGroupIsAppliedToEachMember() throws {
        let all = try nodes(VStack(spacing: 10) {
            Group {
                Color.red.frame(width: 50, height: 20)
                Color.blue.frame(width: 50, height: 20)
            }.padding(5)
        })
        XCTAssertEqual(all.filter { $0.kind == "modifier.padding" }.count, 2, "one padding per member")
        let colors = all.filter { $0.kind == "Color" }
        // each padded member is 60 x 30; the stack puts 10 between them
        XCTAssertEqual(colors.map(\.frame.minY), [5, 45])
        XCTAssertEqual(colors.map(\.frame.minX), [5, 5])
        XCTAssertEqual(all.first?.frame.height, 70)
    }

    func testChainedModifiersOnAGroupDistributeInOrder() throws {
        let all = try nodes(VStack(spacing: 0) {
            Group { Color.red.frame(width: 10, height: 10); Color.blue.frame(width: 10, height: 10) }.padding(2).opacity(0.5)
        })
        XCTAssertEqual(all.filter { $0.kind == "modifier.opacity" }.count, 2)
        XCTAssertEqual(all.filter { $0.kind == "modifier.padding" }.count, 2)
        XCTAssertEqual(all.filter { $0.kind == "Color" }.map(\.frame.minY), [2, 16], "(2 + 10 + 2) per member")
    }

    func testAGroupAsABodyWithAModifierDistributes() throws {
        struct Body: View {
            var body: some View { Group { Color.red.frame(width: 10, height: 10); Color.blue.frame(width: 10, height: 10) }.padding(3) }
        }
        let all = try nodes(HStack(spacing: 0) { Body() })
        XCTAssertEqual(all.filter { $0.kind == "modifier.padding" }.count, 2)
    }

    func testAnEmptyGroupTakesNoSpace() throws {
        let all = try nodes(VStack(spacing: 10) {
            Color.red.frame(width: 10, height: 10)
            Group {}.padding(5)
            Color.blue.frame(width: 10, height: 10)
        })
        XCTAssertEqual(all.filter { $0.kind == "Color" }.map(\.frame.minY), [0, 20])
    }

    func testGroupMembersKeepTheirIdentityAcrossRefresh() throws {
        struct Counter: View {
            @State var n = 0
            var body: some View { Color.red.frame(width: CGFloat(10 + n), height: 10) }
        }
        let g = graph(VStack { Group { Counter(); Counter() }.padding(1) })
        let before = flatten(try XCTUnwrap(g.snapshot())).map(\.instance)
        g.flush()
        XCTAssertEqual(flatten(try XCTUnwrap(g.snapshot())).map(\.instance), before)
    }

    private func flatten(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(flatten) }

    // MARK: ViewModifier

    private struct Framed: ViewModifier {
        let inset: CGFloat
        func body(content: Content) -> some View { content.padding(inset).background(Color.red) }
    }

    func testAViewModifierBodyAppliesToItsContent() throws {
        let all = try nodes(Color.blue.frame(width: 30, height: 10).modifier(Framed(inset: 4)), w: nil, h: nil)
        let background = try XCTUnwrap(all.first { $0.kind == "Background" })
        XCTAssertEqual(frame(background), [0, 0, 38, 18], "30 x 10 plus 4 pt on each side")
        XCTAssertEqual(frame(background.children[0]), [0, 0, 38, 18], "the red layer fills the padded view")
        let blue = try XCTUnwrap(all.last { $0.kind == "Color" })
        XCTAssertEqual(frame(blue), [4, 4, 30, 10])
    }

    private struct Tall: ViewModifier {
        func body(content: Content) -> some View { content.frame(height: 40) }
    }

    func testViewModifiersChain() throws {
        let all = try nodes(Color.blue.frame(width: 30, height: 10).modifier(Tall()).modifier(Framed(inset: 1)), w: nil, h: nil)
        let background = try XCTUnwrap(all.first { $0.kind == "Background" })
        XCTAssertEqual(frame(background), [0, 0, 32, 42])
    }

    // MARK: background

    func testBackgroundFillsTheViewFrameBehindIt() throws {
        let all = try nodes(Color.blue.frame(width: 50, height: 20).background(Color.red), w: nil, h: nil)
        let background = try XCTUnwrap(all.first { $0.kind == "Background" })
        XCTAssertEqual(frame(background), [0, 0, 50, 20])
        XCTAssertEqual(background.children.count, 2)
        XCTAssertEqual(frame(background.children[0]), [0, 0, 50, 20], "the first child (painted first, so behind) is the background layer")
        XCTAssertEqual(frame(background.children[1]), [0, 0, 50, 20])
        XCTAssertEqual(background.children[1].kind, "modifier.frame", "the view itself is the last child, painted above")
    }

    func testBackgroundDoesNotChangeLayout() throws {
        let plain = try nodes(HStack(spacing: 5) { Color.blue.frame(width: 50, height: 20); Color.green.frame(width: 10, height: 10) }).filter { $0.kind == "Color" }
        let backed = try nodes(HStack(spacing: 5) { Color.blue.frame(width: 50, height: 20).background(Color.red.frame(width: 200, height: 100)); Color.green.frame(width: 10, height: 10) })
        XCTAssertEqual(backed.first { $0.kind == "Background" }.map(frame), [0, 0, 50, 20], "a larger background does not grow the view")
        XCTAssertEqual(backed.filter { $0.kind == "Color" }.last?.frame, plain.last?.frame, "the sibling is where it was")
        let red = try XCTUnwrap(backed.first { $0.kind == "Color" })
        XCTAssertEqual(frame(red), [-75, -40, 200, 100], "centred on the view")
    }

    func testBackgroundAlignment() throws {
        let all = try nodes(Color.blue.frame(width: 50, height: 20).background(Color.red.frame(width: 10, height: 6), alignment: .topLeading), w: nil, h: nil)
        XCTAssertEqual(all.first { $0.kind == "Color" }.map(frame), [0, 0, 10, 6])
        let bottomTrailing = try nodes(Color.blue.frame(width: 50, height: 20).background(alignment: .bottomTrailing) { Color.red.frame(width: 10, height: 6) }, w: nil, h: nil)
        XCTAssertEqual(bottomTrailing.first { $0.kind == "Color" }.map(frame), [40, 14, 10, 6])
    }

    func testBackgroundIsOfferedTheViewSize() throws {
        // a flexible background takes the view's size, whatever the parent offers
        let all = try nodes(Color.blue.frame(width: 50, height: 20).background(Color.red.frame(maxWidth: .infinity, maxHeight: .infinity)))
        XCTAssertEqual(all.first { $0.kind == "Background" }.map(frame), [0, 0, 50, 20])
        XCTAssertEqual(all.first { $0.kind == "Color" }.map(frame), [0, 0, 50, 20])
    }

    func testBackgroundInAShape() throws {
        let all = try nodes(Color.blue.frame(width: 50, height: 20).background(Color.red, in: Circle()), w: nil, h: nil)
        let background = try XCTUnwrap(all.first { $0.kind == "Background" })
        XCTAssertEqual(background.children[0].kind, "Circle")
        XCTAssertEqual(frame(background.children[0]), [0, 0, 50, 20])
        XCTAssertEqual(frame(background), [0, 0, 50, 20])
    }

    // MARK: offset

    func testOffsetPaintsShiftedAndKeepsTheLayoutFrame() throws {
        let all = try nodes(HStack(spacing: 0) {
            Color.red.frame(width: 50, height: 20).offset(x: 10, y: 5)
            Color.blue.frame(width: 50, height: 20)
        })
        let offset = try XCTUnwrap(all.first { $0.kind == "modifier.offset" })
        XCTAssertEqual(frame(offset), [0, 0, 50, 20], "the layout frame is unchanged")
        let colors = all.filter { $0.kind == "Color" }
        XCTAssertEqual(frame(colors[0]), [10, 5, 50, 20], "painted at +10, +5")
        XCTAssertEqual(frame(colors[1]), [50, 0, 50, 20], "the sibling does not move")
        XCTAssertEqual(all.first?.frame.width, 100)
    }

    func testOffsetTakesASizeAndNegativeValues() throws {
        let all = try nodes(Color.red.frame(width: 50, height: 20).offset(CGSize(width: -4, height: 2)), w: nil, h: nil)
        XCTAssertEqual(all.first { $0.kind == "Color" }.map(frame), [-4, 2, 50, 20])
        XCTAssertEqual(all.first?.frame.width, 50)
    }

    func testOffsetsAdd() throws {
        let all = try nodes(Color.red.frame(width: 10, height: 10).offset(x: 3).offset(y: 4), w: nil, h: nil)
        XCTAssertEqual(all.first { $0.kind == "Color" }.map(frame), [3, 4, 10, 10])
    }

    func testOffsetIsNotMirroredUnderRightToLeft() throws {
        let all = try nodes(Color.red.frame(width: 10, height: 10).offset(x: 6).environment(\.layoutDirection, .rightToLeft), w: nil, h: nil)
        XCTAssertEqual(all.first { $0.kind == "Color" }.map(frame), [6, 0, 10, 10], "positive x is to the right in either direction")
    }

    // MARK: position

    func testPositionTakesTheProposalAndCentresTheChildAtThePoint() throws {
        let all = try nodes(Color.red.frame(width: 20, height: 10).position(x: 100, y: 50))
        XCTAssertEqual(all.first.map(frame), [0, 0, 300, 200], "the whole proposed space")
        XCTAssertEqual(all.first { $0.kind == "modifier.position" }.map(frame), [0, 0, 300, 200])
        XCTAssertEqual(all.first { $0.kind == "Color" }.map(frame), [90, 45, 20, 10], "centred at (100, 50)")
    }

    func testPositionTakesAPoint() throws {
        let all = try nodes(Color.red.frame(width: 20, height: 10).position(CGPoint(x: 0, y: 0)))
        XCTAssertEqual(all.first { $0.kind == "Color" }.map(frame), [-10, -5, 20, 10])
    }

    func testPositionPointIsInTheModifierSpace() throws {
        // inside a 100 x 60 frame the point is relative to the frame's corner, wherever the frame sits
        let all = try nodes(VStack(spacing: 0) {
            Color.blue.frame(width: 100, height: 30)
            Color.red.frame(width: 20, height: 10).position(x: 30, y: 20).frame(width: 100, height: 60)
        }, w: 300, h: 200)
        let red = try XCTUnwrap(all.last { $0.kind == "Color" })
        XCTAssertEqual(frame(red), [20, 30 + 15, 20, 10])
    }

    func testPositionWithoutAProposalIsTheChildSize() throws {
        let all = try nodes(Color.red.frame(width: 20, height: 10).position(x: 100, y: 50), w: nil, h: nil)
        XCTAssertEqual(all.first.map(frame), [0, 0, 20, 10])
    }

    // MARK: GeometryReader

    private final class Sizes { var seen: [CGSize] = []; var local: [CGRect] = [] }

    func testGeometryReaderTakesTheProposalAndReportsIt() throws {
        let box = Sizes()
        let all = try nodes(GeometryReader { proxy in
            Color.red.frame(width: proxy.size.width / 2, height: proxy.size.height / 2).onAppear { box.local.append(proxy.frame(in: .local)) }
        }, w: 200, h: 100)
        let reader = try XCTUnwrap(all.first { $0.kind == "GeometryReader" })
        XCTAssertEqual(frame(reader), [0, 0, 200, 100])
        XCTAssertEqual(all.first { $0.kind == "Color" }.map(frame), [0, 0, 100, 50], "content at the top-leading corner, at its own size")
        XCTAssertEqual(box.local.last, CGRect(x: 0, y: 0, width: 200, height: 100))
    }

    func testGeometryReaderContentSeesTheLaidOutSizeInTheSameFlush() throws {
        let box = Sizes()
        let g = graph(GeometryReader { proxy in
            Color.red.frame(width: 10, height: 10).onAppear { box.seen.append(proxy.size) }
        }, w: 200, h: 100)
        XCTAssertEqual(box.seen.last, CGSize(width: 200, height: 100))
        _ = g
    }

    func testGeometryReaderRebuildsWhenItsSizeChanges() throws {
        let g = graph(GeometryReader { proxy in Color.red.frame(width: proxy.size.width, height: 10) }, w: 200, h: 100)
        func red() throws -> ResolvedNode { try XCTUnwrap(flatten(try XCTUnwrap(g.snapshot())).first { $0.kind == "Color" }) }
        XCTAssertEqual(try red().frame.width, 200)
        g.rootProposal = ProposedViewSize(width: 120, height: 60)
        g.flush()
        XCTAssertEqual(try red().frame.width, 120)
        XCTAssertEqual(g.snapshot()?.frame.width, 120)
    }

    func testGeometryReaderInAStackTakesWhatItIsOffered() throws {
        let box = Sizes()
        let all = try nodes(VStack(spacing: 0) {
            GeometryReader { proxy in Color.red.frame(width: 5, height: 5).onAppear { box.seen.append(proxy.size) } }.frame(height: 40)
            Color.blue.frame(width: 10, height: 10)
        }, w: 200, h: 100)
        XCTAssertEqual(box.seen.last, CGSize(width: 200, height: 40), "full proposed width, the frame's height")
        XCTAssertEqual(all.first { $0.kind == "GeometryReader" }.map(frame), [0, 0, 200, 40])
        XCTAssertEqual(all.first { $0.kind == "GeometryReader" }.map { $0.frame.minY }, 0)
    }

    func testGeometryReaderWithoutAProposalIsTenPoints() throws {
        let all = try nodes(GeometryReader { _ in Color.red.frame(width: 1, height: 1) }, w: nil, h: nil)
        XCTAssertEqual(all.first.map(frame), [0, 0, 10, 10])
    }

    // MARK: allowsHitTesting (runtime side; the host side is in SwiftRightHostTests)

    private final class Taps { var count = 0; var hover: [Bool] = [] }

    func testAllowsHitTestingFalseBlocksTapsAndHover() throws {
        let taps = Taps()
        let g = graph(VStack(spacing: 0) {
            Color.red.frame(width: 50, height: 20).onTapGesture { taps.count += 1 }.onHover { taps.hover.append($0) }.allowsHitTesting(false)
            Color.blue.frame(width: 50, height: 20).onTapGesture { taps.count += 10 }
        })
        XCTAssertFalse(g.tapGesture(atX: 10, y: 10), "the first row takes no hits")
        XCTAssertEqual(taps.count, 0)
        g.pointerMoved(toX: 10, y: 10)
        XCTAssertEqual(taps.hover, [])
        XCTAssertTrue(g.tapGesture(atX: 10, y: 30), "the second row is unaffected")
        XCTAssertEqual(taps.count, 10)
    }

    func testAllowsHitTestingTrueChangesNothingAndAnAncestorCannotBeOverridden() throws {
        let taps = Taps()
        let g = graph(VStack(spacing: 0) {
            Color.red.frame(width: 50, height: 20).onTapGesture { taps.count += 1 }.allowsHitTesting(true)
            VStack(spacing: 0) { Color.blue.frame(width: 50, height: 20).onTapGesture { taps.count += 10 }.allowsHitTesting(true) }.allowsHitTesting(false)
        })
        XCTAssertTrue(g.tapGesture(atX: 10, y: 10))
        XCTAssertEqual(taps.count, 1)
        XCTAssertFalse(g.tapGesture(atX: 10, y: 30), "a descendant cannot re-enable what an ancestor disabled")
        XCTAssertEqual(taps.count, 1)
    }

    func testAllowsHitTestingIsPublishedOnTheResolvedNodesBelowIt() throws {
        let all = try nodes(VStack(spacing: 0) {
            Color.red.frame(width: 50, height: 20).allowsHitTesting(false)
            Color.blue.frame(width: 50, height: 20)
        })
        let colors = all.filter { $0.kind == "Color" }
        XCTAssertEqual(colors.map(\.accessibility.allowsHitTesting), [false, true])
        XCTAssertEqual(all.first?.accessibility.allowsHitTesting, true)
    }
}
