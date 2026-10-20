#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_r5_digits_view_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("0123456789 1111").font(Font.system(size: 13))
            Text("0123456789 1111").font(Font.system(size: 13)).monospacedDigit()
            Text("10:48 1111").font(Font.system(size: 22, weight: .semibold))
            Text("10:48 1111").font(Font.system(size: 22, weight: .semibold)).monospacedDigit()
        }
    }
}

struct Witness_r5_digits_view_v1: View {
    var body: some View { Witness_f2_digits_v1_inner().frame(width: 240, height: 200, alignment: .topLeading) }
}
