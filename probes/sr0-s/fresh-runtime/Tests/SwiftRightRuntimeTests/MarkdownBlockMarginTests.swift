import Foundation
import SwiftRightRuntime
import XCTest

// Issue #74 pass 2: MarkdownUI's BlockSequence (a @State dictionary fed by onPreferenceChange(BlockMarginsPreference), read back as `.padding(.top, max(top, predecessor.bottom))`)
// must settle on the margins the blocks asked for (with patch 0006's read of the state in `body`). On Windows the gaps between top-level blocks were 16 (the default padding of a nil length), the Mac 13 (1 em at 13 pt).

private struct TestMargin: Equatable {
    var top: CGFloat?
    var bottom: CGFloat?
}

private struct TestMarginKey: PreferenceKey {
    static let defaultValue = TestMargin()
    static func reduce(value: inout TestMargin, nextValue: () -> TestMargin) {
        let next = nextValue()
        value.top = [value.top, next.top].compactMap { $0 }.max()
        value.bottom = [value.bottom, next.bottom].compactMap { $0 }.max()
    }
}

private struct TestBlock: View {
    var height: CGFloat
    var bottom: CGFloat
    var body: some View {
        // the shape MarkdownUI uses: a view that reads the environment and applies markdownMargin through transformPreference
        TestReader {
            Color.red.frame(width: 10, height: height)
                .transformPreference(TestMarginKey.self) { value in
                    value.top = [value.top, CGFloat(0)].compactMap { $0 }.max()
                    value.bottom = [value.bottom, bottom].compactMap { $0 }.max()
                }
        }
    }
}

private struct TestReader<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content
    var body: some View { content() }
}

private struct TestSequence: View {
    @State private var margins: [Int: TestMargin] = [:]
    let blocks: [(height: CGFloat, bottom: CGFloat)]

    var body: some View {
        // patch 0006: the rows read `margins` when the stack expands them, outside this body's observation scope (a runtime gap: ForEach row closures are not tracked);
        // reading it here makes the body depend on it
        _ = margins
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.indices), id: \.self) { index in
                TestBlock(height: blocks[index].height, bottom: blocks[index].bottom)
                    .onPreferenceChange(TestMarginKey.self) { value in margins[index] = value }
                    .padding(.top, topPadding(index))
            }
        }
    }

    private func topPadding(_ index: Int) -> CGFloat? {
        guard index > 0 else { return 0 }
        return [margins[index]?.top, margins[index - 1]?.bottom].compactMap { $0 }.max()
    }
}

@MainActor
final class MarkdownBlockMarginTests: XCTestCase {
    func testBlockSequenceSettlesOnPreferenceMargins() throws {
        let g = Graph(TestSequence(blocks: [(24, 13), (16, 13), (16, 13)]), scale: 1)
        g.rootProposal = ProposedViewSize(width: 300, height: 200)
        g.flush()
        g.flush()
        func walk(_ n: ResolvedNode) -> [ResolvedNode] { [n] + n.children.flatMap(walk) }
        let reds = walk(try XCTUnwrap(g.snapshot())).filter { $0.kind == "Color" }
        // 0..24, gap 13, 37..53, gap 13, 66..82 (a default padding of 16 would give 40 and 72)
        XCTAssertEqual(reds.map(\.frame.minY), [0, 37, 66])
    }
}
