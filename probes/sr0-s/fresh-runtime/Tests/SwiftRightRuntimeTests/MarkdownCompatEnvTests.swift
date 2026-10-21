import XCTest
@testable import SwiftRightRuntime

// Issue #68 pass 3: environment/preference transforms and the small SwiftUI APIs MarkdownUI needs.

@MainActor
private final class Log<T> {
    var values: [T] = []
}

private struct EnvProbe<V>: View {
    let keyPath: KeyPath<EnvironmentValues, V>
    let log: Log<V>
    @Environment private var value: V

    init(_ keyPath: KeyPath<EnvironmentValues, V>, log: Log<V>) {
        self.keyPath = keyPath
        self.log = log
        _value = Environment(keyPath)
    }

    var body: some View {
        let _ = log.values.append(value)
        Rectangle().fill(Color.red).frame(width: 10, height: 10)
    }
}

private struct LabelKey: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}

private struct MaxKey: PreferenceKey {
    static let defaultValue: Int = 0
    static func reduce(value: inout Int, nextValue: () -> Int) { value = max(value, nextValue()) }
}

private struct ListKey: EnvironmentKey {
    static var defaultValue: [String] { [] }
}

extension EnvironmentValues {
    fileprivate var testList: [String] {
        get { self[ListKey.self] }
        set { self[ListKey.self] = newValue }
    }
}

@MainActor
final class MarkdownCompatEnvTests: XCTestCase {
    private func settle<V: View>(_ view: V) -> Graph {
        let graph = Graph(view, scale: 2)
        graph.rootProposal = ProposedViewSize(width: 200, height: 200)
        graph.flush()
        return graph
    }

    func testTransformEnvironmentRewritesFromTheInheritedValue() {
        let log = Log<[String]>()
        _ = settle(
            EnvProbe(\.testList, log: log)
                .transformEnvironment(\.testList) { $0.append("inner") }
                .transformEnvironment(\.testList) { $0.append("outer") }
                .environment(\.testList, ["base"])
        )
        // the outermost modifier applies first: base, then outer, then inner reaches the probe
        XCTAssertEqual(log.values.last, ["base", "outer", "inner"])
    }

    func testTransformEnvironmentStartsFromDefault() {
        let log = Log<[String]>()
        _ = settle(EnvProbe(\.testList, log: log).transformEnvironment(\.testList) { $0 = $0 + ["x"] })
        XCTAssertEqual(log.values.last, ["x"])
    }

    func testTransformPreferenceRewritesTheReducedSubtreeValue() {
        let log = Log<Int>()
        _ = settle(
            VStack {
                Rectangle().fill(Color.red).frame(width: 5, height: 5).preference(key: MaxKey.self, value: 3)
                Rectangle().fill(Color.red).frame(width: 5, height: 5).preference(key: MaxKey.self, value: 7)
            }
            .transformPreference(MaxKey.self) { $0 += 100 }
            .onPreferenceChange(MaxKey.self) { log.values.append($0) }
        )
        XCTAssertEqual(log.values.last, 107)
    }

    func testTransformPreferenceWithNoContributorsSeesTheDefault() {
        let log = Log<[String]>()
        _ = settle(
            Rectangle().fill(Color.red).frame(width: 5, height: 5)
                .transformPreference(LabelKey.self) { $0.append("margin") }
                .onPreferenceChange(LabelKey.self) { log.values.append($0) }
        )
        XCTAssertEqual(log.values.last, ["margin"])
    }

    func testTransformPreferenceOutsideInnerOrder() {
        let log = Log<[String]>()
        _ = settle(
            Rectangle().fill(Color.red).frame(width: 5, height: 5)
                .preference(key: LabelKey.self, value: ["leaf"])
                .transformPreference(LabelKey.self) { $0.append("inner") }
                .transformPreference(LabelKey.self) { $0.append("outer") }
                .onPreferenceChange(LabelKey.self) { log.values.append($0) }
        )
        XCTAssertEqual(log.values.last, ["leaf", "inner", "outer"])
    }

    func testMultilineTextAlignmentEnvironment() {
        let defaultLog = Log<TextAlignment>()
        _ = settle(EnvProbe(\.multilineTextAlignment, log: defaultLog))
        XCTAssertEqual(defaultLog.values.last, .leading)

        let log = Log<TextAlignment>()
        _ = settle(EnvProbe(\.multilineTextAlignment, log: log).multilineTextAlignment(.center))
        XCTAssertEqual(log.values.last, .center)
        XCTAssertEqual(TextAlignment.allCases.count, 3)
    }

    func testForegroundColorEqualsForegroundStyle() {
        let a = Log<ResolvedColor?>()
        let b = Log<ResolvedColor?>()
        _ = settle(EnvProbe(\.foregroundStyle, log: a).foregroundColor(Color.blue))
        _ = settle(EnvProbe(\.foregroundStyle, log: b).foregroundStyle(Color.blue))
        XCTAssertNotNil(a.values.last ?? nil)
        XCTAssertEqual(a.values.last ?? nil, b.values.last ?? nil)
    }

    func testForegroundColorNilRestoresDefault() {
        let log = Log<ResolvedColor?>()
        _ = settle(EnvProbe(\.foregroundStyle, log: log).foregroundColor(nil).foregroundStyle(Color.red))
        XCTAssertNil(log.values.last ?? nil)
    }

    func testOpenURLDefaultUsesTheHostOpener() {
        let saved = OpenURLAction.systemOpener
        defer { OpenURLAction.systemOpener = saved }
        final class Box: @unchecked Sendable { var urls: [URL] = [] }
        let box = Box()
        OpenURLAction.systemOpener = { box.urls.append($0); return true }
        let url = URL(string: "https://example.com/a")!
        EnvironmentValues().openURL(url)
        XCTAssertEqual(box.urls, [url])
        var accepted: Bool?
        EnvironmentValues().openURL(url) { accepted = $0 }
        XCTAssertEqual(accepted, true)
    }

    func testOpenURLDefaultWithoutHostOpenerIsNotAccepted() {
        let saved = OpenURLAction.systemOpener
        defer { OpenURLAction.systemOpener = saved }
        OpenURLAction.systemOpener = nil
        var accepted: Bool?
        EnvironmentValues().openURL(URL(string: "https://example.com")!) { accepted = $0 }
        XCTAssertEqual(accepted, false)
    }

    func testOpenURLCustomHandlerResults() {
        let saved = OpenURLAction.systemOpener
        defer { OpenURLAction.systemOpener = saved }
        final class Box: @unchecked Sendable { var urls: [URL] = [] }
        let box = Box()
        OpenURLAction.systemOpener = { box.urls.append($0); return true }

        var seen: [URL] = []
        var environment = EnvironmentValues()
        let handled = URL(string: "app://handled")!
        let discarded = URL(string: "app://discarded")!
        let system = URL(string: "https://example.com/system")!
        let redirected = URL(string: "https://example.com/redirect")!
        let replacement = URL(string: "https://example.com/replacement")!
        environment.openURL = OpenURLAction { url in
            seen.append(url)
            switch url {
            case handled: return .handled
            case discarded: return .discarded
            case redirected: return .systemAction(replacement)
            default: return .systemAction
            }
        }
        var results: [Bool] = []
        for url in [handled, discarded, system, redirected] { environment.openURL(url) { results.append($0) } }
        XCTAssertEqual(seen, [handled, discarded, system, redirected])
        XCTAssertEqual(results, [true, false, true, true])
        XCTAssertEqual(box.urls, [system, replacement])
    }

    func testOpenURLEnvironmentReachesViews() {
        let log = Log<Bool>()
        struct Reader: View {
            let log: Log<Bool>
            @Environment(\.openURL) private var openURL
            var body: some View {
                let _ = openURL(URL(string: "app://x")!) { log.values.append($0) }
                Rectangle().fill(Color.red).frame(width: 4, height: 4)
            }
        }
        _ = settle(Reader(log: log).environment(\.openURL, OpenURLAction { _ in .handled }))
        XCTAssertEqual(log.values.last, true)
    }

    func testScaledMetricReturnsBaseValue() {
        struct Holder {
            @ScaledMetric(relativeTo: .body) var size: CGFloat = 17
            @ScaledMetric var plain: Double = 3
        }
        let holder = Holder()
        XCTAssertEqual(holder.size, 17)
        XCTAssertEqual(holder.plain, 3)

        struct Explicit {
            @ScaledMetric private var size: CGFloat
            init(_ size: CGFloat?) { self._size = ScaledMetric(wrappedValue: size ?? 14, relativeTo: .body) }
            var value: CGFloat { size }
        }
        XCTAssertEqual(Explicit(nil).value, 14)
        XCTAssertEqual(Explicit(20).value, 20)
    }

    func testTextAttributedAndConcatenation() {
        let joined = Text("a") + Text(AttributedString("b")) + Text(Image(systemName: "star"))
        XCTAssertEqual(joined.string, "ab")
    }
}
