#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_disabled: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: .constant(30), in: 0...100).frame(width: 200)
            Slider(value: .constant(30), in: 0...100).disabled(true).frame(width: 200)
            Slider(value: .constant(70), in: 0...100).frame(width: 200)
            Slider(value: .constant(70), in: 0...100).disabled(true).frame(width: 200)
            Slider(value: .constant(100), in: 0...100).disabled(true).frame(width: 200)
            Slider(value: .constant(0), in: 0...100).disabled(true).frame(width: 200)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
