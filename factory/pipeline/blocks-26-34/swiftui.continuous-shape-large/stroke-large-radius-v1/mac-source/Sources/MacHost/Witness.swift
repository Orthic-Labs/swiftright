#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_cl_stroke_large: View {
    var body: some View {
        VStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 13.1, style: .continuous).stroke(Color.red, lineWidth: 1).frame(width: 100, height: 40)
            RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(Color.blue, lineWidth: 1).frame(width: 100, height: 40)
            RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.green, lineWidth: 1).frame(width: 100, height: 40)
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.orange, lineWidth: 1).frame(width: 100, height: 30)
        }.frame(width: 240, height: 200)
    }
}
