import Foundation
import XCTest
@testable import SwiftRightRuntime

/// Additive diagnostic using unchanged original PerformanceTests workload types.
@MainActor
final class PerformancePhaseDiagnosisTests: XCTestCase {
    func testMatchedOriginalWorkload() throws {
        let store = PerfStore(rows: 200)
        let measurer = FixedAdvanceTextMeasurer()
        let graph = Graph(PerfScreen(store: store), measurer: measurer, scale: 2.5)
        graph.rootProposal = ProposedViewSize(width: 960, height: 640)
        graph.flush()
        graph.profile = GraphProfile()
        var observations: [[String: Any]] = []
        func capture(_ workload: String, _ body: (Int) -> Void) -> Double {
            var walls: [Double] = []
            for i in 0..<30 {
                graph.profile = GraphProfile()
                let requests = measurer.requests.count
                let start = DispatchTime.now().uptimeNanoseconds
                body(i)
                let wall = DispatchTime.now().uptimeNanoseconds - start
                let p = graph.profile!
                observations.append([
                    "workload": workload, "sample": i, "warmup": i < 5,
                    "wallNS": wall, "evaluateNS": p.evaluateNS, "layoutNS": p.layoutNS,
                    "diffNS": p.diffNS, "transactionNS": p.transactionNS,
                    "resolveNS": p.resolveNS, "sinkNS": p.sinkNS,
                    "evaluations": p.evaluations, "measurements": measurer.requests.count - requests,
                    "flushes": p.flushes, "commits": p.commits,
                    "liveNodes": p.liveNodes, "resolvedNodes": p.resolvedNodes
                ])
                if i >= 5 { walls.append(Double(wall) / 1e6) }
            }
            return walls.sorted()[walls.count / 2]
        }
        let typing = capture("typing") { i in
            store.typed += 1
            store.activeText = String(repeating: "m", count: i % 30)
            graph.flush()
        }
        let scroll = capture("scroll") { i in
            graph.scroll(graph.ids(ofKind: "ScrollView")[0], to: CGFloat(i * 7))
            graph.flush()
        }
        let rowEdit = capture("rowEdit") { i in
            store.rows[(i * 37) % store.rows.count].text = "Row edited \(i)"
            graph.flush()
        }
        #if DEBUG
        let optimized = false
        #else
        let optimized = true
        #endif
        let payload: [String: Any] = ["schema": "matched-performance-phase-v1", "optimized": optimized,
            "rowCount": 200, "warmup": 5, "runs": 25,
            "limitsMS": ["typing": 2, "scroll": 4, "rowEdit": 15],
            "mediansMS": ["typing": typing, "scroll": scroll, "rowEdit": rowEdit],
            "observations": observations]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print("PHASE_DIAG " + String(decoding: data, as: UTF8.self))
        XCTAssertTrue(optimized, "diagnostic pair requires release optimization")
        XCTAssertLessThan(typing, 2, "original typing commit limit")
        XCTAssertLessThan(scroll, 4, "original scroll-only commit limit")
        XCTAssertLessThan(rowEdit, 15, "original row edit commit limit")
    }
}
