#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #60, case text-tracking-v1: Text.tracking(_:) and Text.kerning(_:) on the bundled Tinos (same font bytes on both sides), beside the same word untracked.
struct Witness_g60_tracking_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Spacing").font(.custom("Tinos-Regular", size: 22)).foregroundStyle(Color.black)
            Text("Spacing").font(.custom("Tinos-Regular", size: 22)).tracking(4).foregroundStyle(Color.black)
            Text("Spacing").font(.custom("Tinos-Regular", size: 22)).kerning(-1).foregroundStyle(Color.black)
        }
    }
}

struct Witness_g60_tracking: View {
    var body: some View { Witness_g60_tracking_inner().frame(width: 260, height: 200, alignment: .topLeading).padding(.leading, 20).padding(.top, 20) }
}
