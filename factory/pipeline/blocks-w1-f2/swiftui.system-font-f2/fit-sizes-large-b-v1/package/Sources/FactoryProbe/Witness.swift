#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_fit_sizes_large_b_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.headline.weight(.regular)).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.headline.weight(.regular)).frame(width: 150, height: 16, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("gjpqy 42").font(Font.headline.weight(.regular)).frame(width: 150, alignment: .leading)
                Text("gjpqy 42").font(Font.headline.weight(.regular)).frame(width: 150, height: 16, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.title3.weight(.semibold)).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.title3.weight(.semibold)).frame(width: 150, height: 19.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("gjpqy 42").font(Font.title3.weight(.semibold)).frame(width: 150, alignment: .leading)
                Text("gjpqy 42").font(Font.title3.weight(.semibold)).frame(width: 150, height: 19.2, alignment: .topLeading)
            }
        }
    }
}

struct Witness_f2_fit_sizes_large_b_v1: View {
    var body: some View { Witness_f2_fit_sizes_large_b_v1_inner().frame(width: 300, height: 200, alignment: .topLeading) }
}
