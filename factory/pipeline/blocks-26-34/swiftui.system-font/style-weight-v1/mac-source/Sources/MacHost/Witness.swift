#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sf_style_weight: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hxg Overview").font(.body.weight(.bold)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(.headline.weight(.regular)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(.title3.weight(.semibold)).frame(width: 240, height: 40, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
