#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R2 (#37), case custom-pair-v1: A user Shape with AnimatablePair<CGFloat, CGFloat> animatableData (a notch-like neck: width and depth) under .easeInOut(duration: 0.6).
struct Neck: Shape {
    var width: CGFloat
    var depth: CGFloat
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(width, depth) }
        set { width = newValue.first; depth = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let mid = rect.midX
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: mid + width / 2, y: rect.minY + depth))
        p.addQuadCurve(to: CGPoint(x: mid - width / 2, y: rect.minY + depth), control: CGPoint(x: mid, y: rect.minY + depth + 20))
        p.closeSubpath()
        return p
    }
}

struct Witness_r2_custom_pair_v1: View {
    @State private var open = false
    var body: some View {
        Neck(width: open ? 160 : 40, depth: open ? 100 : 30)
            .fill(Color.blue)
            .frame(width: 200, height: 140)
            .frame(width: 240, height: 160)
            .onAppear { withAnimation(FactoryAnim.wrap(.easeInOut(duration: 0.6))) { open = true } }
    }
}
