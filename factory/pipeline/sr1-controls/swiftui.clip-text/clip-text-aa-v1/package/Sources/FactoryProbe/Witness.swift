#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #76, case clip-text-aa-v1: the bundled Tinos (same font bytes on both sides) at 40 pt, wider than the 90 pt Circle clip it sits in, so the clip cuts the glyph run.
// Windows fills the run from its glyph outlines (ABI 0.14) with the clip's anti-aliased coverage instead of the renderer's 1 px staircase path clip.
struct Witness_g76_clip_text: View {
    var body: some View {
        Text("Hamburgefon").font(.custom("Tinos-Regular", size: 40)).foregroundStyle(Color.black).fixedSize()
            .frame(width: 90, height: 90)
            .clipShape(Circle())
            .frame(width: 260, height: 200)
    }
}
