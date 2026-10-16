#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_values: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: .constant(0), in: 0...100).frame(width: 200)
            Slider(value: .constant(20), in: 0...100).frame(width: 200)
            Slider(value: .constant(50), in: 0...100).frame(width: 200)
            Slider(value: .constant(80), in: 0...100).frame(width: 200)
            Slider(value: .constant(100), in: 0...100).frame(width: 200)
            Slider(value: .constant(36), in: 0...100).frame(width: 200)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
