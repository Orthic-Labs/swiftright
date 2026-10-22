import SwiftRightRuntime
import XCTest

@MainActor
final class AppStorageTests: XCTestCase {
    struct Probe: View {
        static let suite = UserDefaults(suiteName: "swr.appstorage.tests")!
        @AppStorage("count", store: Probe.suite) var count = 3
        @AppStorage("name", store: Probe.suite) var name: String? = nil
        var body: some View { Text("\(count)-\(name ?? "none")") }
    }

    func testDefaultWriteAndRemove() {
        Probe.suite.removePersistentDomain(forName: "swr.appstorage.tests")
        let p = Probe()
        XCTAssertEqual(p.count, 3)
        p.count = 7
        XCTAssertEqual(Probe.suite.integer(forKey: "count"), 7)
        XCTAssertEqual(Probe().count, 7)
        XCTAssertNil(p.name)
        p.name = "a"
        XCTAssertEqual(Probe.suite.string(forKey: "name"), "a")
        p.name = nil
        XCTAssertNil(Probe.suite.object(forKey: "name"))
        Probe.suite.removePersistentDomain(forName: "swr.appstorage.tests")
    }
}
