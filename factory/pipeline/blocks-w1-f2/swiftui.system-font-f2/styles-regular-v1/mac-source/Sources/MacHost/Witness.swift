#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_styles_regular_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HIEFLT Hxz").font(Font.largeTitle)
            Text("HIEFLT Hxz").font(Font.title)
            Text("HIEFLT Hxz").font(Font.title2)
            Text("HIEFLT Hxz").font(Font.title3)
            Text("HIEFLT Hxz").font(Font.headline)
            Text("HIEFLT Hxz").font(Font.body)
            Text("HIEFLT Hxz").font(Font.callout)
            Text("HIEFLT Hxz").font(Font.subheadline)
            Text("HIEFLT Hxz").font(Font.footnote)
            Text("HIEFLT Hxz").font(Font.caption)
            Text("HIEFLT Hxz").font(Font.caption2)
        }
    }
}

struct Witness_f2_styles_regular_v1: View {
    var body: some View { Witness_f2_styles_regular_v1_inner().frame(width: 240, height: 200, alignment: .topLeading) }
}
