#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sf_sizes: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hxg Overview").font(Font.system(size: 11, weight: .regular)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 12, weight: .regular)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 13, weight: .regular)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 15, weight: .regular)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .regular)).frame(width: 240, height: 40, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
