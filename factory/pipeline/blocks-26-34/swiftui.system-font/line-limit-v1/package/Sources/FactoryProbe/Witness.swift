#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sf_line_limit: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Overview of memory pressure and swap activity across every running process").font(Font.system(size: 12, weight: .regular)).lineLimit(2).frame(width: 110, height: 60, alignment: .leading)
            Text("Overview of memory pressure and swap activity across every running process").font(Font.system(size: 12, weight: .regular)).lineLimit(3).frame(width: 110, height: 60, alignment: .leading)
            Text("Overview of memory pressure").font(Font.system(size: 12, weight: .regular)).lineLimit(3).frame(width: 110, height: 60, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
