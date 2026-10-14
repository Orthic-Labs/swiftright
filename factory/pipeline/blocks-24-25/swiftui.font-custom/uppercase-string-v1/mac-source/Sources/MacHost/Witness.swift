#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_fc_upper_string_inner: View {
    var body: some View {
        Text("PULSE HUB SETTINGS").font(.custom("Tinos-Regular", size: 20)).frame(width: 260, height: 30, alignment: .leading)
    }
}

struct Witness_fc_upper_string: View {
    var body: some View { Witness_fc_upper_string_inner().frame(width: 260, height: 200, alignment: .topLeading) }
}
