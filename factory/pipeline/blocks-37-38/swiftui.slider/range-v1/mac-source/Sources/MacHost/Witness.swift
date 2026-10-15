#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_range: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: .constant(0.4), in: 0...1).frame(width: 200)
            Slider(value: .constant(15), in: 10...20).frame(width: 200)
            Slider(value: .constant(20), in: -50...50).frame(width: 200)
            Slider(value: .constant(4), in: 0...10).frame(width: 200)
            Slider(value: .constant(75), in: 50...100).frame(width: 200)
            Slider(value: .constant(8), in: 0...8).frame(width: 200)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
