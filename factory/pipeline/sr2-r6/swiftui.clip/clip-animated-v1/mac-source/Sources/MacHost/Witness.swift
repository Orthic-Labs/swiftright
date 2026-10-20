#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// SR2 R6 (#41), case clip-animated-v1: a colour clipped by the R2 neck shape (AnimatablePair animatableData) as it opens under .easeInOut(duration: 0.6): the clip animates.
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

struct Witness_r6_clip_animated_v1: View {
    @State private var open = false
    var body: some View {
        Color.blue
            .clipShape(Neck(width: open ? 160 : 40, depth: open ? 100 : 30))
            .frame(width: 200, height: 140)
            .frame(width: 240, height: 160)
            .onAppear { withAnimation(FactoryAnim.wrap(.easeInOut(duration: 0.6))) { open = true } }
    }
}
