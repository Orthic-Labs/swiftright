#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_value_labels: View {
    @State private var a = 40.0
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(value: $a, in: 0...100) { Text("Volume") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
