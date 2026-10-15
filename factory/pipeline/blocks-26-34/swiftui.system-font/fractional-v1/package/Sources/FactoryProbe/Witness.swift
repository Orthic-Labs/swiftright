#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sf_fractional: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hxg Overview").font(Font.system(size: 11.5, weight: .regular)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 12.5, weight: .regular)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 11.5, weight: .semibold)).frame(width: 240, height: 40, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 13, weight: .medium)).frame(width: 240, height: 40, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
