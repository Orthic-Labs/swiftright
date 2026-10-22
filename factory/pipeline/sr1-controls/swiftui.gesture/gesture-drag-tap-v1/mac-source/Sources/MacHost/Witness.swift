#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #84, case gesture-drag-tap-v1: a rectangle dragged with DragGesture (global coordinates; it follows the translation from where the drag started) and a rectangle that
// changes colour on each tap (onTapGesture). Positions are absolute so the pointer steps are the same on both sides.
struct Witness_g84_gesture_drag_tap_v1: View {
    @State private var dragged = CGSize.zero
    @State private var start = CGSize.zero
    @State private var taps = 0
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white
            Rectangle().fill(Color.blue).frame(width: 60, height: 40)
                .offset(x: 70 + dragged.width, y: 40 + dragged.height)
                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                    .onChanged { dragged = CGSize(width: start.width + $0.translation.width, height: start.height + $0.translation.height) }
                    .onEnded { _ in start = dragged })
            Rectangle().fill(taps % 2 == 0 ? Color.green : Color.orange).frame(width: 60, height: 40)
                .offset(x: 70, y: 150)
                .onTapGesture { taps += 1 }
        }
        .frame(width: 320, height: 240)
    }
}
