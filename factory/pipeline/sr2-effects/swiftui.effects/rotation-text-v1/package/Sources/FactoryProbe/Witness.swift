#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #69, case rotation-text-v1: the bundled Tinos (same font bytes on both sides) at 28 pt under rotationEffect(.degrees(30)), and a 15 pt line under -60.
// Windows fills each run from its glyph outlines (renderer ABI 0.14 swr_text_run_outline), rotated by the host path rasterizer.
struct Witness_e69_rotation_text_inner: View {
    var body: some View {
        VStack(spacing: 40) {
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 28)).foregroundStyle(Color.black).rotationEffect(.degrees(30))
            Text("Settings").font(.custom("Tinos-Regular", size: 15)).foregroundStyle(Color.blue).rotationEffect(.degrees(-60))
        }
    }
}

struct Witness_e69_rotation_text: View {
    var body: some View { Witness_e69_rotation_text_inner().frame(width: 260, height: 200) }
}
