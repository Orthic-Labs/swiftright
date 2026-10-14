#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_fc_text_case_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pulse hub settings").font(.custom("Tinos-Regular", size: 20)).textCase(.uppercase).frame(width: 260, height: 30, alignment: .leading)
            Text("PULSE Hub").font(.custom("Tinos-Regular", size: 20)).textCase(.lowercase).frame(width: 260, height: 30, alignment: .leading)
        }
    }
}

struct Witness_fc_text_case: View {
    var body: some View { Witness_fc_text_case_inner().frame(width: 260, height: 200, alignment: .topLeading) }
}
