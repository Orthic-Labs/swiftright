#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_fc_sizes_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Thirteen").font(.custom("Tinos-Regular", size: 13)).frame(width: 240, height: 23, alignment: .leading)
            Text("Eighteen").font(.custom("Tinos-Regular", size: 18)).frame(width: 240, height: 28, alignment: .leading)
            Text("Thirty-one").font(.custom("Tinos-Regular", size: 31)).frame(width: 240, height: 43, alignment: .leading)
        }
    }
}

struct Witness_fc_sizes: View {
    var body: some View { Witness_fc_sizes_inner().frame(width: 260, height: 200, alignment: .topLeading) }
}
