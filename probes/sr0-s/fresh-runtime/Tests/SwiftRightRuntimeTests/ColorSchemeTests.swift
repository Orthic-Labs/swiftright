import SwiftRightRuntime
import XCTest

private struct SchemeProbe: View {
    @Environment(\.colorScheme) var scheme
    var body: some View {
        if scheme == .dark { Rectangle().fill(Color.red).frame(width: 10, height: 10) } else { Rectangle().fill(Color.blue).frame(width: 20, height: 10) }
    }
}

private struct EnvDark: View { var body: some View { SchemeProbe().environment(\.colorScheme, .dark) } }
private struct Plain: View { var body: some View { SchemeProbe() } }
private struct Mixed: View {
    var body: some View { HStack(spacing: 0) { SchemeProbe(); SchemeProbe().environment(\.colorScheme, .dark) } }
}
private struct Preferred: View {
    var body: some View { VStack(spacing: 0) { Rectangle().fill(.background).frame(width: 10, height: 10); SchemeProbe() }.preferredColorScheme(.dark) }
}
private struct PreferredInside: View {
    var body: some View { VStack(spacing: 0) { Rectangle().fill(.primary).frame(width: 10, height: 10); Rectangle().fill(Color.red).frame(width: 4, height: 4).preferredColorScheme(.dark) } }
}
private struct Toggled: View {
    @State var dark = false
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.primary).frame(width: 10, height: 10)
            SchemeProbe().preferredColorScheme(dark ? .dark : nil)
            Button("flip") { dark.toggle() }
        }
    }
}

@MainActor
final class ColorSchemeTests: XCTestCase {
    private func nodes(_ view: some View) -> (Graph, [ResolvedNode]) {
        let graph = Graph(view, scale: 1)
        graph.flush()
        return (graph, everyNode(graph.snapshot()))
    }

    func testEnvironmentReadDefaultsToLight() {
        let (_, all) = nodes(Plain())
        XCTAssertEqual(all.first { $0.kind == "Rectangle" }?.frame.width, 20)
        XCTAssertTrue(all.allSatisfy { $0.style.colorScheme == .light })
    }

    func testEnvironmentModifierSwitchesTheSubtreeAndTheReadBranch() {
        let (_, all) = nodes(EnvDark())
        let rect = all.first { $0.kind == "Rectangle" }
        XCTAssertEqual(rect?.frame.width, 10)
        XCTAssertEqual(rect?.style.colorScheme, .dark)
    }

    func testSiblingsKeepTheirOwnScheme() {
        let (_, all) = nodes(Mixed())
        let rects = all.filter { $0.kind == "Rectangle" }
        XCTAssertEqual(rects.map(\.style.colorScheme), [.light, .dark])
        XCTAssertEqual(rects.map(\.frame.width), [20, 10])
    }

    func testPreferredColorSchemeDarkensTheSubtree() {
        let (_, all) = nodes(Preferred())
        XCTAssertTrue(all.filter { $0.kind == "Rectangle" }.allSatisfy { $0.style.colorScheme == .dark })
        XCTAssertEqual(all.filter { $0.kind == "Rectangle" }.map(\.frame.width), [10, 10])
    }

    func testPreferredColorSchemeReachesViewsOutsideItsSubtree() {
        // as a window appearance on macOS: a sibling that is not under the modifier is dark too
        let (_, all) = nodes(PreferredInside())
        XCTAssertEqual(all.first { $0.kind == "Rectangle" }?.style.colorScheme, .dark)
    }

    func testPreferredColorSchemeNilGivesTheHostSchemeBack() {
        let (graph, _) = nodes(Toggled())
        func schemes() -> [ColorScheme] { everyNode(graph.snapshot()).filter { $0.kind == "Rectangle" }.map(\.style.colorScheme) }
        XCTAssertEqual(schemes(), [.light, .light])
        let button = graph.ids(ofKind: "Button")[0]
        XCTAssertTrue(graph.tapButton(button)); graph.flush()
        XCTAssertEqual(schemes(), [.dark, .dark])
        XCTAssertTrue(graph.tapButton(button)); graph.flush()
        XCTAssertEqual(schemes(), [.light, .light])
    }

    func testSemanticColourNames() {
        XCTAssertEqual(Color.primary.resolvedColor, .semantic("label"))
        XCTAssertEqual(Color.secondary.resolvedColor, .semantic("secondaryLabel"))
        XCTAssertEqual(Color.accentColor.resolvedColor, .semantic("accentColor"))
        XCTAssertEqual(BackgroundStyle().resolvedColor, .semantic("background"))
        let (_, all) = nodes(Rectangle().fill(.background).frame(width: 4, height: 4))
        XCTAssertEqual(all.first { $0.kind == "Rectangle" }?.shape?.paint?.color, .semantic("background"))
    }
}
