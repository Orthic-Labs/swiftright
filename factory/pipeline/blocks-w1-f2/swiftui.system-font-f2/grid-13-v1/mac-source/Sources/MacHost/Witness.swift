#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_grid_13_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(.system(size: 13, weight: .ultraLight)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 13, weight: .thin)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 13, weight: .light)).frame(width: 100, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(.system(size: 13, weight: .regular)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 13, weight: .medium)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 13, weight: .semibold)).frame(width: 100, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(.system(size: 13, weight: .bold)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 13, weight: .heavy)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 13, weight: .black)).frame(width: 100, alignment: .leading)
            }
        }
    }
}

struct Witness_f2_grid_13_v1: View {
    var body: some View { Witness_f2_grid_13_v1_inner().frame(width: 300, height: 200, alignment: .topLeading) }
}
