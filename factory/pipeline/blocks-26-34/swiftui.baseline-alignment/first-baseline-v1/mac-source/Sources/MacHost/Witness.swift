#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_ba_first_baseline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Hxg").font(Font.system(size: 12, weight: .regular)).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 18, weight: .semibold)).frame(width: 40, alignment: .leading)
            Rectangle().fill(Color.blue).frame(width: 12, height: 20).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 11, weight: .regular)).frame(width: 40, alignment: .leading)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
