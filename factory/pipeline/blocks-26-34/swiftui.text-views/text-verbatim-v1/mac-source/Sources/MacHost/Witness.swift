#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_tv_verbatim: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: "**bold** and *em* 100%").frame(width: 240, height: 20, alignment: .leading)
            Text(verbatim: "\\(x) {y} %@ [z](u)").frame(width: 240, height: 20, alignment: .leading)
            Text(verbatim: "plain").frame(width: 240, height: 20, alignment: .leading)
            Rectangle().fill(Color.red).frame(width: 240, height: 20).padding(.top, 10)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
