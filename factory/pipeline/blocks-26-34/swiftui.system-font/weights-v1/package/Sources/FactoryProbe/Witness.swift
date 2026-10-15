#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sf_weights: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hxg Overview").font(Font.system(size: 18, weight: .ultraLight)).frame(width: 240, height: 22, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .thin)).frame(width: 240, height: 22, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .light)).frame(width: 240, height: 22, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .regular)).frame(width: 240, height: 22, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .medium)).frame(width: 240, height: 22, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .semibold)).frame(width: 240, height: 22, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .bold)).frame(width: 240, height: 22, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .heavy)).frame(width: 240, height: 22, alignment: .leading)
            Text("Hxg Overview").font(Font.system(size: 18, weight: .black)).frame(width: 240, height: 22, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
