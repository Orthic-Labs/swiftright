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
    var t0 = Date()
    func late() -> Int { Date().timeIntervalSince(t0) > 0.15 ? 1 : 0 }
}
nonisolated(unsafe) let op = OnchProbe()

struct MarkBar: View {
    let mark: Int
    var body: some View { Rectangle().fill(mark < 0 ? Color.gray : (mark == 1 ? Color.green : Color.red)).frame(width: mark == 1 ? 40 : 8, height: 8) }
}

struct Witness_co_onchg: View {
    @State private var a = 0
    @State private var af = 0
    @State private var b = 0
    @State private var bf = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Plain") { op.t0 = Date(); a = 1 }.frame(width: 100, height: 28)
            Button("Animated") {
                op.t0 = Date()
                withAnimation(.linear(duration: 0.3)) { b = 1 } completion: { op.markB = op.late() }
            }.frame(width: 100, height: 28)
            // direction A: a plain trigger; its onChange writes under withAnimation. The follower (blue) animates, the trigger (white) snaps
            VStack(alignment: .leading, spacing: 2) {
                Color.white.frame(width: CGFloat(a) * 20 + 10, height: 8)
                Color.blue.frame(width: CGFloat(af) * 20 + 10, height: 8)
            }
            .onChange(of: a) { _, new in
                withAnimation(.linear(duration: 0.3)) { af = new } completion: { op.markA = op.late() }
            }
            MarkBar(mark: op.markA)
            // direction B: an animated trigger; its onChange writes under withAnimation(nil). The trigger (white) keeps its animation, the follower (red) snaps
            VStack(alignment: .leading, spacing: 2) {
                Color.white.frame(width: CGFloat(b) * 20 + 10, height: 8)
                Color.red.frame(width: CGFloat(bf) * 20 + 10, height: 8)
            }
            .onChange(of: b) { _, new in
                withAnimation(nil) { bf = new }
            }
            MarkBar(mark: op.markB)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
