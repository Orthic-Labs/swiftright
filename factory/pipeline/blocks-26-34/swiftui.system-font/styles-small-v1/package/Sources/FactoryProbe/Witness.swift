#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sf_styles_small: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hxg Overview").font(.subheadline).frame(width: 240, height: 24, alignment: .leading)
            Text("Hxg Overview").font(.body).frame(width: 240, height: 24, alignment: .leading)
            Text("Hxg Overview").font(.callout).frame(width: 240, height: 24, alignment: .leading)
            Text("Hxg Overview").font(.footnote).frame(width: 240, height: 24, alignment: .leading)
            Text("Hxg Overview").font(.caption).frame(width: 240, height: 24, alignment: .leading)
            Text("Hxg Overview").font(.caption2).frame(width: 240, height: 24, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
