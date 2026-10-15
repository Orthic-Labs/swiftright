#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_ba_nested: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Hxg").font(Font.system(size: 12, weight: .regular)).frame(width: 40, alignment: .leading)
            HStack(spacing: 0) { Rectangle().fill(Color.green).frame(width: 8, height: 30); Text("Hxg").font(Font.system(size: 18)) }.frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) { Text("Hxg").font(Font.system(size: 11)); Text("Hxg").font(Font.system(size: 11)) }.frame(width: 40, alignment: .leading)
            Rectangle().fill(Color.orange).frame(width: 12, height: 18).frame(width: 40, alignment: .leading)
            }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
