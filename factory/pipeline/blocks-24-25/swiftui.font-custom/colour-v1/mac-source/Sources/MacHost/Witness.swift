#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_fc_colour_inner: View {
    var body: some View {
        Text("Pulse Hub").font(.custom("Tinos-Regular", size: 24)).foregroundStyle(Color.red).frame(width: 240, height: 34, alignment: .leading)
    }
}

struct Witness_fc_colour: View {
    var body: some View { Witness_fc_colour_inner().frame(width: 260, height: 200, alignment: .topLeading) }
}
