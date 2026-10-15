#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_ba_frame: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Hxg").font(Font.system(size: 12, weight: .regular)).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 12, weight: .regular)).frame(height: 40).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 18, weight: .regular)).frame(height: 50, alignment: .top).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 11, weight: .regular)).frame(height: 40, alignment: .bottom).frame(width: 40, alignment: .leading)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
