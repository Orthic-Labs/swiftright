#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #82, case canvas-v1: Canvas drawing fills and strokes of paths, with a translate and a scale.
struct Witness_g82_canvas_v1: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(x: 10, y: 10, width: 120, height: 60)), with: .color(.blue))
            context.stroke(Path(roundedRect: CGRect(x: 10, y: 10, width: 120, height: 60), cornerRadius: 12), with: .color(.red), lineWidth: 4)
            var inner = context
            inner.translateBy(x: 150, y: 20)
            inner.scaleBy(x: 2, y: 1)
            inner.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 40, height: 50)), with: .color(.green))
            context.stroke(Path { p in p.move(to: CGPoint(x: 10, y: size.height - 20)); p.addLine(to: CGPoint(x: size.width - 10, y: size.height - 20)) }, with: .color(.black), lineWidth: 2)
        }
        .frame(width: 300, height: 200)
    }
}
