#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_disabled_input: View {
    @State private var a = 30.0
    @State private var b = 30.0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $a, in: 0...100).disabled(true).frame(width: 200)
            Slider(value: $b, in: 0...100).frame(width: 200)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
