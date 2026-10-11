import Foundation

struct CopyCostRow: View {
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Row \(index)")
            HStack(spacing: 4) {
                Text("primary \(index)")
                Text("secondary \(index)")
            }
        }
    }
}

struct CopyCostWorkload: View {
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(0..<count, id: \.self) { index in
                CopyCostRow(index: index)
            }
        }
    }
}

@main
@MainActor
struct CopyCostProbe {
    static func format(_ value: Double) -> String { String(format: "%.6f", value) }

    static func main() {
        let graph = Graph(CopyCostWorkload(count: 200), scale: 2)
        graph.rootProposal = ProposedViewSize(width: 560, height: 900)
        graph.flush()

        var samples: [Double] = []
        samples.reserveCapacity(25)
        for _ in 0..<5 { graph.flush() }
        for _ in 0..<25 {
            let start = DispatchTime.now().uptimeNanoseconds
            graph.flush()
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / 1_000_000.0)
        }
        let sorted = samples.sorted()
        let median = sorted[sorted.count / 2]
        let p95 = sorted[Int(Double(sorted.count - 1) * 0.95)]
        let profile = graph.profile
        print("workloadRows=200")
        print("liveNodes=\(graph.counts().nodes)")
        print("resolvedRootChildren=\(graph.snapshot()?.children.count ?? -1)")
        print("medianFlushMS=\(format(median))")
        print("p95FlushMS=\(format(p95))")
        print("samplesMS=\(samples.map(format).joined(separator: ","))")
        print("profile=\(String(describing: profile))")
    }
}
