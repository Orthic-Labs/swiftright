import Foundation
import SwiftRightRuntime
import XCTest

// Issue #68 (MarkdownUI on SwiftRight): custom alignments and alignment guides, Grid, anchors and anchor preferences, LabelStyle, AnyShapeStyle.
// Expected positions are the documented SwiftUI results worked by hand (the Mac oracle cases are the lead's next step); scale 1 keeps frames unsnapped.

private struct QuarterHeightID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context.height / 4 }
}

private extension VerticalAlignment {
    static let quarterHeight = VerticalAlignment(QuarterHeightID.self)
}

private struct EdgeMarkID: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width }
}

private extension HorizontalAlignment {
    static let edgeMark = HorizontalAlignment(EdgeMarkID.self)
}

private struct CellBoundsKey: PreferenceKey {
    static let defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

@MainActor
private final class DimensionsLog {
    var seen: [ViewDimensions] = []
}

private struct StackedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

@MainActor
final class MarkdownCompatLayoutTests: XCTestCase {
    private func nodes<V: View>(_ view: V, w: CGFloat? = 300, h: CGFloat? = 200) throws -> [ResolvedNode] {
        let g = Graph(view, scale: 1)
        g.rootProposal = ProposedViewSize(width: w, height: h)
        g.flush()
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        return walk(try XCTUnwrap(g.snapshot()))
    }

    private func colors(_ all: [ResolvedNode]) -> [ResolvedNode] { all.filter { $0.kind == "Color" } }

    // MARK: Custom alignments

    func testCustomVerticalAlignmentAlignsOnItsDefaultGuide() throws {
        // guides: 40 / 4 = 10 and 20 / 4 = 5; the line sits at 10, so the shorter view is pushed down by 5; the row is 40 high
        let all = try nodes(HStack(alignment: .quarterHeight, spacing: 0) {
            Color.red.frame(width: 10, height: 40)
            Color.blue.frame(width: 10, height: 20)
        })
        XCTAssertEqual(colors(all).map(\.frame.minY), [0, 5])
        XCTAssertEqual(colors(all).map(\.frame.minX), [0, 10])
        XCTAssertEqual(all.first?.frame.height, 40)
    }

    func testCustomHorizontalAlignmentInAVStack() throws {
        // edgeMark's default guide is the trailing edge: right edges line up
        let all = try nodes(VStack(alignment: .edgeMark, spacing: 0) {
            Color.red.frame(width: 50, height: 10)
            Color.blue.frame(width: 30, height: 10)
        })
        XCTAssertEqual(colors(all).map(\.frame.minX), [0, 20])
        XCTAssertEqual(all.first?.frame.width, 50)
    }

    func testAlignmentGuideShiftsAViewOnAStandardAlignment() throws {
        // blue's leading guide is its trailing edge (30): the line is at 30, so red moves right by 30 and blue stays at 0
        let all = try nodes(VStack(alignment: .leading, spacing: 0) {
            Color.red.frame(width: 50, height: 10)
            Color.blue.frame(width: 30, height: 10).alignmentGuide(.leading) { $0[.trailing] }
        })
        XCTAssertEqual(colors(all).map(\.frame.minX), [30, 0])
        XCTAssertEqual(all.first?.frame.width, 80)
    }

    func testAlignmentGuideWithANegativeValueMovesTheViewRight() throws {
        let all = try nodes(VStack(alignment: .leading, spacing: 0) {
            Color.red.frame(width: 50, height: 10)
            Color.blue.frame(width: 30, height: 10).alignmentGuide(.leading) { $0[.leading] - 20 }
        })
        XCTAssertEqual(colors(all).map(\.frame.minX), [0, 20])
        XCTAssertEqual(all.first?.frame.width, 50)
    }

    func testVerticalAlignmentGuideInAnHStack() throws {
        let all = try nodes(HStack(alignment: .top, spacing: 0) {
            Color.red.frame(width: 10, height: 10)
            Color.blue.frame(width: 10, height: 20).alignmentGuide(.top) { $0[.bottom] }
        })
        XCTAssertEqual(colors(all).map(\.frame.minY), [20, 0])
        XCTAssertEqual(all.first?.frame.height, 30)
    }

    func testAlignmentGuideNeedsNoGuideForOtherAlignments() throws {
        // a guide for .leading does not disturb a centred stack
        let all = try nodes(VStack(spacing: 0) {
            Color.red.frame(width: 50, height: 10)
            Color.blue.frame(width: 30, height: 10).alignmentGuide(.leading) { _ in 99 }
        })
        XCTAssertEqual(colors(all).map(\.frame.minX), [0, 10])
    }

    func testZStackAlignsOnAnAlignmentGuide() throws {
        let all = try nodes(ZStack(alignment: .leading) {
            Color.red.frame(width: 50, height: 10)
            Color.blue.frame(width: 30, height: 10).alignmentGuide(.leading) { $0[.trailing] }
        })
        XCTAssertEqual(colors(all).map(\.frame.minX), [30, 0])
        XCTAssertEqual(all.first?.frame.width, 80)
    }

    func testOverlayAlignsOnAnAlignmentGuide() throws {
        let all = try nodes(Color.red.frame(width: 50, height: 50).overlay(alignment: .leading) {
            Color.blue.frame(width: 10, height: 10).alignmentGuide(.leading) { $0[.trailing] }
        })
        let blue = try XCTUnwrap(colors(all).last)
        XCTAssertEqual(blue.frame.minX, -10)
        XCTAssertEqual(blue.frame.minY, 20)
    }

    func testViewDimensionsReportSizeAndGuides() throws {
        let log = DimensionsLog()
        _ = try nodes(VStack(alignment: .leading) {
            Color.red.frame(width: 40, height: 20).alignmentGuide(.leading) { d in
                log.seen.append(d)
                return 0
            }
        })
        let d = try XCTUnwrap(log.seen.last)
        XCTAssertEqual(d.width, 40)
        XCTAssertEqual(d.height, 20)
        XCTAssertEqual(d[.leading], 0)
        XCTAssertEqual(d[.trailing], 40)
        XCTAssertEqual(d[HorizontalAlignment.center], 20)
        XCTAssertEqual(d[.top], 0)
        XCTAssertEqual(d[.bottom], 20)
        XCTAssertEqual(d[VerticalAlignment.center], 10)
        XCTAssertEqual(d[.firstTextBaseline], 20, "a view with no text has its bottom edge as its baseline")
        XCTAssertNil(d[explicit: HorizontalAlignment.leading])
        XCTAssertEqual(d[.quarterHeight], 5, "a custom alignment reads its default value")
    }

    func testGuideOfAnInnerViewIsSeenThroughPadding() throws {
        // the inner view's leading guide is its trailing edge (10); padding(5) moves it to 15 in the padded view
        let all = try nodes(VStack(alignment: .leading, spacing: 0) {
            Color.red.frame(width: 40, height: 10)
            Color.blue.frame(width: 10, height: 10).alignmentGuide(.leading) { $0[.trailing] }.padding(5)
        })
        // blue padded: width 20, guide 15; red guide 0; line 15: red x 15, padded blue x 0 (blue x 5)
        XCTAssertEqual(colors(all).map(\.frame.minX), [15, 5])
    }

    // MARK: Grid

    func testGridColumnsAreAsWideAsTheirWidestCellAndRowsAsTallAsTheirTallest() throws {
        let all = try nodes(Grid(horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Color.red.frame(width: 20, height: 10)
                Color.blue.frame(width: 50, height: 30)
            }
            GridRow {
                Color.green.frame(width: 40, height: 20)
                Color.yellow.frame(width: 10, height: 10)
            }
        })
        let cells = colors(all)
        XCTAssertEqual(all.first?.frame.width, 100)   // 40 + 10 + 50
        XCTAssertEqual(all.first?.frame.height, 54)   // 30 + 4 + 20
        // centred in their cell areas: column widths 40 and 50, row heights 30 and 20
        XCTAssertEqual(cells.map(\.frame.minX), [10, 50, 0, 70])
        XCTAssertEqual(cells.map(\.frame.minY), [10, 0, 34, 39])
    }

    func testGridAlignmentPlacesCellsInTheirAreas() throws {
        let all = try nodes(Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 4) {
            GridRow {
                Color.red.frame(width: 20, height: 10)
                Color.blue.frame(width: 50, height: 30)
            }
            GridRow {
                Color.green.frame(width: 40, height: 20)
                Color.yellow.frame(width: 10, height: 10)
            }
        })
        XCTAssertEqual(colors(all).map(\.frame.minX), [0, 50, 0, 50])
        XCTAssertEqual(colors(all).map(\.frame.minY), [0, 0, 34, 34])
    }

    func testGridColumnAlignmentAppliesToTheWholeColumn() throws {
        let all = try nodes(Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                Color.red.frame(width: 20, height: 10).gridColumnAlignment(.trailing)
                Color.blue.frame(width: 50, height: 10)
            }
            GridRow {
                Color.green.frame(width: 40, height: 10)
                Color.yellow.frame(width: 10, height: 10)
            }
        })
        // column 0 is 40 wide and trailing-aligned: red at 20, green at 0; column 1 keeps the grid's leading alignment
        XCTAssertEqual(colors(all).map(\.frame.minX), [20, 50, 0, 50])
    }

    func testGridRowAlignmentOverridesTheGridsVerticalAlignment() throws {
        let all = try nodes(Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow(alignment: .bottom) {
                Color.red.frame(width: 10, height: 10)
                Color.blue.frame(width: 10, height: 30)
            }
        })
        XCTAssertEqual(colors(all).map(\.frame.minY), [20, 0])
    }

    func testGridFlexibleColumnTakesTheRemainingWidth() throws {
        let all = try nodes(Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                Color.red.frame(width: 50, height: 10)
                Color.blue.frame(maxWidth: .infinity).frame(height: 10)
            }
        })
        XCTAssertEqual(all.first?.frame.width, 300)
        let cells = colors(all)
        XCTAssertEqual(cells.map(\.frame.minX), [0, 60])
        XCTAssertEqual(cells.last?.frame.width, 240)
    }

    func testGridDividerSpansTheGridWidth() throws {
        let all = try nodes(Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                Color.red.frame(width: 30, height: 10)
                Color.blue.frame(width: 20, height: 10)
            }
            Divider()
        })
        let divider = try XCTUnwrap(all.first { $0.kind == "Divider" })
        XCTAssertEqual(divider.frame.width, 50)
        XCTAssertEqual(divider.frame.minY, 10)
    }

    // MARK: Anchors

    func testAnchorBoundsResolveInTheReadersCoordinateSpace() throws {
        let all = try nodes(
            VStack(spacing: 10) {
                Color.red.frame(width: 30, height: 20)
                    .anchorPreference(key: CellBoundsKey.self, value: .bounds) { [0: $0] }
                Color.blue.frame(width: 50, height: 40)
                    .anchorPreference(key: CellBoundsKey.self, value: .bounds) { [1: $0] }
            }
            .backgroundPreferenceValue(CellBoundsKey.self) { anchors in
                GeometryReader { proxy in
                    let r = anchors[1].map { proxy[$0] } ?? .zero
                    Color.green.frame(width: r.width, height: r.height)
                        .padding(.leading, r.minX)
                        .padding(.top, r.minY)
                }
            }
        )
        // the VStack is 50 x 70; blue sits at (0, 30)
        let green = try XCTUnwrap(colors(all).first { $0.frame.width == 50 && $0.frame.height == 40 && $0.frame.minY == 30 })
        XCTAssertEqual(green.frame.minX, 0)
        XCTAssertEqual(colors(all).filter { $0.frame.width == 50 }.count, 2, "the blue cell and the green background built from its anchor")
    }

    func testOverlayPreferenceValueSeesTheSameAnchors() throws {
        let all = try nodes(
            VStack(spacing: 0) {
                Color.red.frame(width: 30, height: 20)
                    .anchorPreference(key: CellBoundsKey.self, value: .bounds) { [0: $0] }
                Color.blue.frame(width: 50, height: 40)
            }
            .overlayPreferenceValue(CellBoundsKey.self) { anchors in
                GeometryReader { proxy in
                    let r = anchors[0].map { proxy[$0] } ?? .zero
                    Color.green.frame(width: r.width, height: r.height).padding(.leading, r.minX).padding(.top, r.minY)
                }
            }
        )
        // red is centred in the 50-wide stack: x 10, y 0
        let green = try XCTUnwrap(colors(all).last)
        XCTAssertEqual([green.frame.minX, green.frame.minY, green.frame.width, green.frame.height], [10, 0, 30, 20])
    }

    // Issue #74: MarkdownUI's table decoration reads the anchors of cells built by ForEach inside Grid/GridRow; the inside divider sits in the gap between the columns.
    func testAnchorsOfGridCellsResolveForAnOverlayLayer() throws {
        let all = try nodes(
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                ForEach(0..<2, id: \.self) { row in
                    GridRow {
                        ForEach(0..<2, id: \.self) { column in
                            Color.red.frame(width: column == 0 ? 30 : 40, height: 20)
                                .anchorPreference(key: CellBoundsKey.self, value: .bounds) { [row * 2 + column: $0] }
                        }
                    }
                }
            }
            .padding(1)
            .overlayPreferenceValue(CellBoundsKey.self) { anchors in
                GeometryReader { proxy in
                    let left = anchors[0].map { proxy[$0] } ?? .zero
                    Color.green.frame(width: 1, height: 41).padding(.leading, left.maxX).padding(.top, 1)
                }
            },
            w: 200, h: 100
        )
        // cell (0,0) spans x 1...31 inside the 1 pt padding, so the divider sits at x 31
        let green = try XCTUnwrap(colors(all).first { $0.frame.width == 1 && $0.frame.height == 41 })
        XCTAssertEqual(green.frame.minX, 31)
    }

    func testAnchorSourceCanNameAPointOfTheBounds() throws {
        let all = try nodes(
            Color.red.frame(width: 30, height: 20)
                .anchorPreference(key: PointKey.self, value: Anchor<CGPoint>.Source.bottomTrailing) { $0 }
                .backgroundPreferenceValue(PointKey.self) { anchor in
                    GeometryReader { proxy in
                        let p = anchor.map { proxy[$0] } ?? .zero
                        Color.green.frame(width: 4, height: 4).padding(.leading, p.x).padding(.top, p.y)
                    }
                }
        )
        let green = try XCTUnwrap(colors(all).first { $0.frame.width == 4 })
        XCTAssertEqual([green.frame.minX, green.frame.minY], [30, 20])
    }

    // MARK: LabelStyle

    func testLabelStyleTitleOnlyAndIconOnly() throws {
        func label() -> some View {
            Label {
                Color.blue.frame(width: 20, height: 6)
            } icon: {
                Color.red.frame(width: 10, height: 10)
            }
        }
        let titleOnly = colors(try nodes(label().labelStyle(.titleOnly)))
        XCTAssertEqual(titleOnly.map(\.frame.width), [20])
        let iconOnly = colors(try nodes(label().labelStyle(.iconOnly)))
        XCTAssertEqual(iconOnly.map(\.frame.width), [10])
    }

    func testTitleAndIconStyleKeepsTheLabelsOwnLayout() throws {
        let plain = colors(try nodes(Label { Color.blue.frame(width: 20, height: 6) } icon: { Color.red.frame(width: 10, height: 10) }))
        let styled = colors(try nodes(Label { Color.blue.frame(width: 20, height: 6) } icon: { Color.red.frame(width: 10, height: 10) }.labelStyle(.titleAndIcon)))
        XCTAssertEqual(plain.map(\.frame.minX), [0, 18], "icon, then title 8 pt apart (macOS 27)")
        XCTAssertEqual(styled.map(\.frame.minX), plain.map(\.frame.minX))
        XCTAssertEqual(styled.map(\.frame.minY), plain.map(\.frame.minY))
    }

    func testCustomLabelStyleBuildsTheLabelFromItsConfiguration() throws {
        let all = try nodes(
            Label { Color.blue.frame(width: 20, height: 6) } icon: { Color.red.frame(width: 10, height: 10) }
                .labelStyle(StackedLabelStyle())
        )
        let cells = colors(all)
        XCTAssertEqual(cells.map(\.frame.minY), [0, 12], "icon above title with the style's 2 pt spacing")
        XCTAssertEqual(cells.map(\.frame.minX), [5, 0], "a VStack centres the narrower icon over the wider title")
    }

    func testNearestLabelStyleWins() throws {
        let cells = colors(try nodes(
            Label { Color.blue.frame(width: 20, height: 6) } icon: { Color.red.frame(width: 10, height: 10) }
                .labelStyle(.iconOnly)
                .labelStyle(.titleOnly)
        ))
        XCTAssertEqual(cells.map(\.frame.width), [10], "the inner .iconOnly applies")
    }

    // MARK: AnyShapeStyle

    func testAnyShapeStyleResolvesToTheWrappedStyle() {
        XCTAssertEqual(AnyShapeStyle(Color.red).resolvedColor, Color.red.resolvedColor)
        XCTAssertEqual(AnyShapeStyle(Color.red.opacity(0.5)).resolvedColor, Color.red.opacity(0.5).resolvedColor)
        XCTAssertEqual(AnyShapeStyle(BackgroundStyle()).resolvedColor, BackgroundStyle().resolvedColor)
    }

    func testAnyShapeStyleFillsAShape() throws {
        let all = try nodes(Rectangle().fill(AnyShapeStyle(Color.blue)).frame(width: 20, height: 10))
        XCTAssertTrue(all.contains { $0.frame.width == 20 && $0.frame.height == 10 })
    }

    // MARK: CGRectUnion

#if !canImport(CoreGraphics)
    func testCGRectUnionJoinsRectsAndNullIsTheIdentity() {
        let a = CGRect(x: 0, y: 0, width: 10, height: 10)
        let b = CGRect(x: 20, y: 5, width: 5, height: 20)
        XCTAssertEqual(CGRectUnion(a, b), CGRect(x: 0, y: 0, width: 25, height: 25))
        XCTAssertEqual(CGRectUnion(.null, a), a)
        XCTAssertEqual(CGRectUnion(a, .null), a)
        XCTAssertEqual([a, b].reduce(.null, CGRectUnion), CGRect(x: 0, y: 0, width: 25, height: 25))
    }
#endif
}

private struct PointKey: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil
    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = nextValue() ?? value
    }
}

@MainActor final class LabelAccessibilityTests: XCTestCase {
    func testALabelIconIsHiddenFromAccessibility() throws {
        let g = Graph(Label("Title", systemImage: "circle.fill"), scale: 2.5); g.flush()
        var images: [Bool] = [], titles: [Bool] = []
        func walk(_ n: ResolvedNode, hidden: Bool) {
            let hidden = hidden || n.accessibility.isHidden
            if n.kind == "Image" { images.append(hidden) }
            if n.kind == "Text" { titles.append(hidden) }
            n.children.forEach { walk($0, hidden: hidden) }
        }
        walk(try XCTUnwrap(g.snapshot()), hidden: false)
        XCTAssertEqual(images, [true], "the icon is decorative")
        XCTAssertEqual(titles, [false])
    }

    // Issue #78: Font.italic() sets Metadata.isItalic and later modifiers keep it.
    func testFontItalicFlagSurvivesLaterModifiers() {
        let plain = Font.custom("Tinos-Regular", size: 22)
        XCTAssertFalse(plain.metadata?.isItalic ?? true)
        let italic = plain.italic()
        XCTAssertEqual(italic.metadata?.isItalic, true)
        XCTAssertEqual(italic.weight(.bold).metadata?.isItalic, true)
        XCTAssertEqual(italic.monospacedDigit().metadata?.isItalic, true)
        XCTAssertEqual(plain.weight(.bold).metadata?.isItalic, false)
    }
}
