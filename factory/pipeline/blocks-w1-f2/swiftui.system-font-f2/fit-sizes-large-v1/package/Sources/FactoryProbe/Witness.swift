#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_fit_sizes_large_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.system(size: 28, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.system(size: 28, weight: .regular)).frame(width: 150, height: 33.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("gjpqy 42").font(Font.system(size: 28, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("gjpqy 42").font(Font.system(size: 28, weight: .regular)).frame(width: 150, height: 33.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.system(size: 15, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.system(size: 15, weight: .regular)).frame(width: 150, height: 19.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("gjpqy 42").font(Font.system(size: 15, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("gjpqy 42").font(Font.system(size: 15, weight: .regular)).frame(width: 150, height: 19.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("HIH").font(Font.system(size: 18, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("HIH").font(Font.system(size: 18, weight: .regular)).frame(width: 150, height: 21.2, alignment: .topLeading)
            }
            HStack(alignment: .top, spacing: 0) {
                Text("gjpqy 42").font(Font.system(size: 18, weight: .regular)).frame(width: 150, alignment: .leading)
                Text("gjpqy 42").font(Font.system(size: 18, weight: .regular)).frame(width: 150, height: 21.2, alignment: .topLeading)
            }
        }
    }
}

struct Witness_f2_fit_sizes_large_v1: View {
    var body: some View { Witness_f2_fit_sizes_large_v1_inner().frame(width: 300, height: 200, alignment: .topLeading) }
}
