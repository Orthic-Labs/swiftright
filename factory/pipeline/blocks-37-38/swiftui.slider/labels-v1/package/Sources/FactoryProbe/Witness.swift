#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_labels: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: .constant(40), in: 0...100) { Text("Volume") }
            Slider(value: .constant(40), in: 0...100) { Text("Volume") } minimumValueLabel: { Text("0") } maximumValueLabel: { Text("100") }
            Slider(value: .constant(60), in: 0...100, step: 10) { Text("Step") } minimumValueLabel: { Text("Lo") } maximumValueLabel: { Text("Hi") }
            HStack { Text("A"); Slider(value: .constant(40), in: 0...100); Text("B") }
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
