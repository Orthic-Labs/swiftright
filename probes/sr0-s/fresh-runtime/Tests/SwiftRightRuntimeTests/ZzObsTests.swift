import SwiftRightRuntime
import XCTest
import Observation

@Observable final class ObsProbe { var taps: [String: Int] = [:]; var n = 0 }
nonisolated(unsafe) let obsProbe = ObsProbe()
private struct Counter: View {
    let id: String
    var body: some View { Rectangle().fill(Color.black).frame(width: CGFloat(obsProbe.taps[id, default: 0]) * 10 + 1, height: 5) }
}
private struct Counter2: View {
    var body: some View { Rectangle().fill(Color.black).frame(width: CGFloat(obsProbe.n) * 10 + 1, height: 5) }
}
private struct Host: View { var body: some View { VStack { Counter(id: "a"); Counter2() } } }
@MainActor final class ZzObsTests: XCTestCase {
    func testDict() {
        let g = Graph(Host(), scale: 2.5); g.flush()
        func ws() -> [CGFloat] { var out: [CGFloat] = []; func w(_ n: ResolvedNode) { if n.kind == "Rectangle" { out.append(n.frame.width) }; n.children.forEach(w) }; w(g.snapshot()!); return out }
        print("DBG before", ws())
        obsProbe.taps["a", default: 0] += 1; obsProbe.n += 1
        g.flush()
        print("DBG after", ws())
    }
}
