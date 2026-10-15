#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

#if !os(Windows)
import Observation
#endif

@Observable final class HoverProbe {
    var hovered: String? = nil
    var log: [String] = []
    var taps: [String: Int] = [:]
    func record(_ id: String, _ inside: Bool) { log.append(id + (inside ? "+" : "-")); if inside { hovered = id } else if hovered == id { hovered = nil } }
    func tap(_ id: String) { taps[id, default: 0] += 1 }
}
nonisolated(unsafe) let probe = HoverProbe()

/// One square per event, in order: a view's entry is its bright colour, its exit the dark one.
func hoverEventColor(_ e: String) -> Color {
    let up = e.hasSuffix("+")
    switch e.first {
    case "A": return up ? Color.green : Color(red: 0, green: 0.4, blue: 0)
    case "B": return up ? Color.blue : Color(red: 0, green: 0, blue: 0.45)
    case "C": return up ? Color.orange : Color(red: 0.5, green: 0.25, blue: 0)
    case "D": return up ? Color.purple : Color(red: 0.25, green: 0, blue: 0.3)
    default: return Color.gray
    }
}

struct HoverStrip: View {
    var body: some View {
        HStack(spacing: 2) { ForEach(0..<probe.log.count, id: \.self) { i in Rectangle().fill(hoverEventColor(probe.log[i])).frame(width: 10, height: 10) } }
            .frame(width: 240, height: 10, alignment: .leading)
    }
}

struct TapCounter: View {
    let id: String
    var body: some View {
        HStack(spacing: 2) { ForEach(0..<4, id: \.self) { i in Rectangle().fill(probe.taps[id, default: 0] > i ? Color.black : Color(white: 0.85)).frame(width: 8, height: 8) } }
    }
}

#if !os(Windows)
@MainActor enum HoverStandIn {
    static var frames: [(String, CGRect)] = []
    static var hoverable: Set<String> = [], tappable: Set<String> = [], inside: Set<String> = []
    static func install(_ frames: [(String, CGRect)], hover: [String] = [], tap: [String] = []) {
        self.frames = frames; hoverable = Set(hover); tappable = Set(tap); inside = []
        FactoryStandIn.move = { p in update(p) }
        FactoryStandIn.leave = { update(nil) }
        FactoryStandIn.click = { p in if let hit = HoverStandIn.frames.last(where: { HoverStandIn.tappable.contains($0.0) && $0.1.contains(p) }) { probe.tap(hit.0) } }
    }
    /// exits first, then entries, each in tree order (decision H6)
    static func update(_ p: CGPoint?) {
        let now = Set(frames.filter { hoverable.contains($0.0) && p != nil && $0.1.contains(p!) }.map { $0.0 })
        for (id, _) in frames where inside.contains(id) && !now.contains(id) { probe.record(id, false) }
        for (id, _) in frames where !inside.contains(id) && now.contains(id) { probe.record(id, true) }
        inside = now
    }
}
#endif

struct Witness_hv_adjacent: View {
    init() {
#if !os(Windows)
        HoverStandIn.install([("A", CGRect(x: 0, y: 0, width: 100, height: 28)), ("B", CGRect(x: 100, y: 0, width: 100, height: 28))], hover: ["A", "B"], tap: [])
#endif
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Rectangle().fill(probe.hovered == "A" ? Color.green : Color.gray).frame(width: 100, height: 28).onHover { probe.record("A", $0) }
                Rectangle().fill(probe.hovered == "B" ? Color.blue : Color(white: 0.7)).frame(width: 100, height: 28).onHover { probe.record("B", $0) }
            }
            HoverStrip()
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
