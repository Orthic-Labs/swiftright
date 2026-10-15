#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_grid_9_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(.system(size: 9, weight: .ultraLight)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 9, weight: .thin)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 9, weight: .light)).frame(width: 100, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(.system(size: 9, weight: .regular)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 9, weight: .medium)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 9, weight: .semibold)).frame(width: 100, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(.system(size: 9, weight: .bold)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 9, weight: .heavy)).frame(width: 100, alignment: .leading)
                Text("HIH").font(.system(size: 9, weight: .black)).frame(width: 100, alignment: .leading)
            }
        }
    }
}

struct Witness_f2_grid_9_v1: View {
    var body: some View { Witness_f2_grid_9_v1_inner().frame(width: 300, height: 200, alignment: .topLeading) }
}
