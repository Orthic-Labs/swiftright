#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_f2_baseline_hstack_v1_inner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("HIH").font(Font.system(size: 11)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 13)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 17)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 22)).frame(width: 52, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("HIH").font(Font.largeTitle).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.body).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.caption).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.headline).frame(width: 52, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("HIH").font(Font.system(size: 9)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 16, weight: .semibold)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 24)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 32, weight: .light)).frame(width: 52, alignment: .leading)
            }
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("HIH").font(Font.system(size: 13, design: .monospaced)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 13, design: .serif)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 13)).frame(width: 52, alignment: .leading)
                Text("HIH").font(Font.system(size: 13, design: .rounded)).frame(width: 52, alignment: .leading)
            }
        }
    }
}

struct Witness_f2_baseline_hstack_v1: View {
    var body: some View { Witness_f2_baseline_hstack_v1_inner().frame(width: 240, height: 200, alignment: .topLeading) }
}
