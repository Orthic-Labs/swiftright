#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f0_title_sweep_b_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 30)).frame(width: 240, height: 37, alignment: .leading)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 31)).frame(width: 240, height: 39, alignment: .leading)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 32)).frame(width: 240, height: 40, alignment: .leading)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 36)).frame(width: 240, height: 44, alignment: .leading)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 20)).frame(width: 240, height: 26, alignment: .leading)
        }
    }
}

struct Witness_f0_title_sweep_b_v1: View {
    var body: some View { Witness_f0_title_sweep_b_v1_inner().frame(width: 260, height: 200, alignment: .topLeading) }
}
