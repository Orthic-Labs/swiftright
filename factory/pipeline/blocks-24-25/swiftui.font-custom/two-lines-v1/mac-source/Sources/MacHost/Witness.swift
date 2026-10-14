#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_fc_two_lines_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pulse").font(.custom("Tinos-Regular", size: 36)).frame(width: 240, height: 48, alignment: .leading)
            Text("Hub overview").font(.custom("Tinos-Regular", size: 16)).frame(width: 240, height: 25, alignment: .leading)
        }
    }
}

struct Witness_fc_two_lines: View {
    var body: some View { Witness_fc_two_lines_inner().frame(width: 260, height: 200, alignment: .topLeading) }
}
