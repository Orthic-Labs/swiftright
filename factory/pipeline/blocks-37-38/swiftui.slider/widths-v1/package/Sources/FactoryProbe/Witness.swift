#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_widths: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: .constant(60), in: 0...100).frame(width: 240)
            Slider(value: .constant(60), in: 0...100).frame(width: 120)
            Slider(value: .constant(60), in: 0...100).frame(width: 61)
            Slider(value: .constant(50), in: 0...100).frame(width: 30)
            Slider(value: .constant(90), in: 0...100).frame(width: 20.4)
            Slider(value: .constant(40), in: 0...100)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
