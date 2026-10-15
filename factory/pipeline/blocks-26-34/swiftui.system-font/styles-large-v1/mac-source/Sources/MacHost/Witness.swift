#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sf_styles_large: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hxg Overview").font(.largeTitle).frame(width: 240, height: 36, alignment: .leading)
            Text("Hxg Overview").font(.title).frame(width: 240, height: 36, alignment: .leading)
            Text("Hxg Overview").font(.title2).frame(width: 240, height: 36, alignment: .leading)
            Text("Hxg Overview").font(.title3).frame(width: 240, height: 36, alignment: .leading)
            Text("Hxg Overview").font(.headline).frame(width: 240, height: 36, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
