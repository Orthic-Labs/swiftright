#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sf_sizes_large: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hxg Overview").font(Font.system(size: 24, weight: .regular)).frame(width: 240, height: 60, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 28, weight: .regular)).frame(width: 240, height: 60, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 32, weight: .regular)).frame(width: 240, height: 60, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
