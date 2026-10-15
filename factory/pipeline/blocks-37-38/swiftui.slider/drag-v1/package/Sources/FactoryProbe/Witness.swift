#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_drag: View {
    @State private var a = 20.0
    @State private var b = 20.0
    @State private var c = 0.0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $a, in: 0...100).frame(width: 200)
            Slider(value: $b, in: 0...100, step: 10).frame(width: 200)
            Slider(value: $c, in: 0...1).frame(width: 200)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
