#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_hub_theme_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hub Total 82%").font(Font.system(size: 22, weight: .semibold))
            Text("Hub Total 82%").font(Font.system(size: 15, weight: .bold))
            Text("Hub Total 82%").font(Font.system(size: 13.5))
            Text("Hub Total 82%").font(Font.system(size: 13))
            Text("Hub Total 82%").font(Font.system(size: 12.5, weight: .semibold))
            Text("Hub Total 82%").font(Font.system(size: 12))
            Text("Hub Total 82%").font(Font.system(size: 11.5))
            Text("Hub Total 82%").font(Font.system(size: 11, weight: .semibold))
            Text("Hub Total 82%").font(Font.system(size: 22, weight: .semibold))
        }
    }
}

struct Witness_f2_hub_theme_v1: View {
    var body: some View { Witness_f2_hub_theme_v1_inner().frame(width: 240, height: 200, alignment: .topLeading) }
}
