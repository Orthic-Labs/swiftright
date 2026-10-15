#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f0_title_sweep_a_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 24)).frame(width: 240, height: 30, alignment: .leading)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 26)).frame(width: 240, height: 33, alignment: .leading)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 27)).frame(width: 240, height: 34, alignment: .leading)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 28)).frame(width: 240, height: 35, alignment: .leading)
            Text("Pulse Hub").font(.custom("Tinos-Regular", size: 29)).frame(width: 240, height: 36, alignment: .leading)
        }
    }
}

struct Witness_f0_title_sweep_a_v1: View {
    var body: some View { Witness_f0_title_sweep_a_v1_inner().frame(width: 260, height: 200, alignment: .topLeading) }
}
