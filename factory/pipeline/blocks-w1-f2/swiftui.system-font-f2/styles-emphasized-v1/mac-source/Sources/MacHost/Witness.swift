#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_styles_emphasized_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("HIEFLT Hxz").font(Font.largeTitle.bold())
            Text("HIEFLT Hxz").font(Font.title.bold())
            Text("HIEFLT Hxz").font(Font.title2.bold())
            Text("HIEFLT Hxz").font(Font.title3.bold())
            Text("HIEFLT Hxz").font(Font.headline.bold())
            Text("HIEFLT Hxz").font(Font.body.bold())
            Text("HIEFLT Hxz").font(Font.callout.bold())
            Text("HIEFLT Hxz").font(Font.subheadline.bold())
            Text("HIEFLT Hxz").font(Font.footnote.bold())
            Text("HIEFLT Hxz").font(Font.caption.bold())
            Text("HIEFLT Hxz").font(Font.caption2.bold())
        }
    }
}

struct Witness_f2_styles_emphasized_v1: View {
    var body: some View { Witness_f2_styles_emphasized_v1_inner().frame(width: 240, height: 200, alignment: .topLeading) }
}
