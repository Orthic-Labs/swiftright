#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_ba_padding: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Hxg").font(Font.system(size: 12, weight: .regular)).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 12, weight: .regular)).padding(.top, 10).frame(width: 40, alignment: .leading)
            Text("Hxg").font(Font.system(size: 18, weight: .regular)).padding(.top, 4).frame(width: 40, alignment: .leading)
            Rectangle().fill(Color.red).frame(width: 12, height: 14).frame(width: 40, alignment: .leading)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
