#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_ba_last_baseline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("Hxg Hxg Hxg Hxg").font(Font.system(size: 12)).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 12, weight: .regular)).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 18, weight: .semibold)).frame(width: 40, alignment: .leading)
            Rectangle().fill(Color.purple).frame(width: 12, height: 10).frame(width: 40, alignment: .leading)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
