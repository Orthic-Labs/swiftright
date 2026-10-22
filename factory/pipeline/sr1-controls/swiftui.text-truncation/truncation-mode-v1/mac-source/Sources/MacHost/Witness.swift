#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #82, case truncation-mode-v1: lineLimit(1) text wider than its 200 pt frame, truncated at the head, in the middle and at the tail (bundled Tinos, same bytes on both sides).
struct Witness_g82_truncation_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The quick brown fox jumps over the lazy dog").font(.custom("Tinos-Regular", size: 22)).lineLimit(1).truncationMode(.head).foregroundStyle(Color.black).frame(width: 200, alignment: .leading)
            Text("The quick brown fox jumps over the lazy dog").font(.custom("Tinos-Regular", size: 22)).lineLimit(1).truncationMode(.middle).foregroundStyle(Color.black).frame(width: 200, alignment: .leading)
            Text("The quick brown fox jumps over the lazy dog").font(.custom("Tinos-Regular", size: 22)).lineLimit(1).truncationMode(.tail).foregroundStyle(Color.black).frame(width: 200, alignment: .leading)
        }
    }
}

struct Witness_g82_truncation: View {
    var body: some View { Witness_g82_truncation_inner().frame(width: 260, height: 200, alignment: .topLeading).padding(.leading, 20).padding(.top, 20) }
}
