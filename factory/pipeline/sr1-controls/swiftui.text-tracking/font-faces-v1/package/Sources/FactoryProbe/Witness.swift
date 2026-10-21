#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #78, case font-faces-v1: the bundled Tinos Bold and Italic files (same Google Fonts commit as Regular), and the two ways SwiftUI reaches those faces from Regular:
// .weight(.bold) and .italic() on .custom("Tinos-Regular"). Same font bytes on both sides.
struct Witness_g78_faces_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pulse Hub").font(.custom("Tinos-Bold", size: 22)).foregroundStyle(Color.black)
            Text("Pulse Hub").font(.custom("Tinos-Italic", size: 22)).foregroundStyle(Color.black)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 22).weight(.bold)).foregroundStyle(Color.black)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 22).italic()).foregroundStyle(Color.black)
        }
    }
}

struct Witness_g78_faces: View {
    var body: some View { Witness_g78_faces_inner().frame(width: 260, height: 200, alignment: .topLeading).padding(.leading, 20).padding(.top, 20) }
}
