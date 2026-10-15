#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_design_serif_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HIEFLT Hxz 0123").font(Font.system(size: 13, weight: .regular, design: .serif))
            Text("HIEFLT Hxz 0123").font(Font.system(size: 13, weight: .bold, design: .serif))
            Text("HIEFLT Hxz").font(Font.system(size: 20, weight: .regular, design: .serif))
            Text("HIEFLT").font(Font.system(size: 28, weight: .light, design: .serif))
        }
    }
}

struct Witness_f2_design_serif_v1: View {
    var body: some View { Witness_f2_design_serif_v1_inner().frame(width: 240, height: 200, alignment: .topLeading) }
}
