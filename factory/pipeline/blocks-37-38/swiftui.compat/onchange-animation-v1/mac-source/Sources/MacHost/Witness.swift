#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

#if !os(Windows)
import Observation
#endif

@Observable final class CompatProbe {
    var a = 0
    var b = 0
    var tasks = 0
    var values: [Int] = []
    var changes: [[Int]] = []
}
nonisolated(unsafe) let cp = CompatProbe()

struct CountStrip: View {
    let n: Int
    let color: Color
    var body: some View {
        HStack(spacing: 2) { ForEach(0..<8, id: \.self) { i in Rectangle().fill(i < n ? color : Color(white: 0.88)).frame(width: 8, height: 8) } }
    }
}

@Observable final class OnchProbe {
    var markA = -1
    var markB = -1
    var markC1 = -1
    var markC2 = -1
    var t0 = Date()
    func late() -> Int { Date().timeIntervalSince(t0) > 0.15 ? 1 : 0 }
}
nonisolated(unsafe) let op = OnchProbe()

struct MarkBar: View {
    let mark: Int
    var body: some View { Rectangle().fill(mark < 0 ? Color.gray : (mark == 1 ? Color.green : Color.red)).frame(width: mark == 1 ? 40 : 8, height: 6) }
}

struct Witness_co_onchg: View {
    @State private var a = 0
    @State private var af = 0
    @State private var b = 0
    @State private var bf = 0
    @State private var c = 0
    @State private var cf = 0
    @State private var ct = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Plain") { op.t0 = Date(); a = 1 }.frame(width: 100, height: 28)
            Button("Animated") {
                op.t0 = Date()
                withAnimation(.linear(duration: 0.3)) { b = 1 } completion: { op.markB = op.late() }
            }.frame(width: 100, height: 28)
            Button("Nested") { op.t0 = Date(); c = 1 }.frame(width: 100, height: 28)
            // direction A: a plain trigger; its onChange writes under withAnimation. The follower (blue) animates, the trigger (orange, visible on the white background) snaps
            VStack(alignment: .leading, spacing: 1) {
                Color.orange.frame(width: CGFloat(a) * 20 + 10, height: 6)
                Color.blue.frame(width: CGFloat(af) * 20 + 10, height: 6)
            }
            .onChange(of: a) { _, new in
                withAnimation(.linear(duration: 0.3)) { af = new } completion: { op.markA = op.late() }
            }
            MarkBar(mark: op.markA)
            // direction B: an animated trigger; its onChange writes under withAnimation(nil). The trigger (orange) keeps its animation, the follower (red) snaps
            VStack(alignment: .leading, spacing: 1) {
                Color.orange.frame(width: CGFloat(b) * 20 + 10, height: 6)
                Color.red.frame(width: CGFloat(bf) * 20 + 10, height: 6)
            }
            .onChange(of: b) { _, new in
                withAnimation(nil) { bf = new }
            }
            MarkBar(mark: op.markB)
            // direction C: a plain trigger; its onChange nests an inner withAnimation (0.25 s) in an outer one (0.4 s). The outer completion (first bar) runs late
            // if the outer animation animated the follower; the inner completion (second bar) runs late only if the inner transaction governed the inner write
            // (third), at once if the outer one decided for it. Both are measured; neither is assumed. (Run 38913665384, Mac: both bars green, inner governs its own writes.)
            VStack(alignment: .leading, spacing: 1) {
                Color.orange.frame(width: CGFloat(c) * 20 + 10, height: 6)
                Color.blue.frame(width: CGFloat(cf) * 20 + 10, height: 6)
                Color.purple.frame(width: CGFloat(ct) * 20 + 10, height: 6)
            }
            .onChange(of: c) { _, new in
                withAnimation(.linear(duration: 0.4)) {
                    cf = new
                    withAnimation(.linear(duration: 0.25)) { ct = new } completion: { op.markC2 = op.late() }
                } completion: { op.markC1 = op.late() }
            }
            HStack(spacing: 4) { MarkBar(mark: op.markC1); MarkBar(mark: op.markC2) }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
