#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_fc_title_32_inner: View {
    var body: some View {
        Text("Pulse Hub").font(.custom("Tinos-Regular", size: 32)).frame(width: 240, height: 44, alignment: .leading)
    }
}

struct Witness_fc_title_32: View {
    var body: some View { Witness_fc_title_32_inner().frame(width: 260, height: 200, alignment: .topLeading) }
}
