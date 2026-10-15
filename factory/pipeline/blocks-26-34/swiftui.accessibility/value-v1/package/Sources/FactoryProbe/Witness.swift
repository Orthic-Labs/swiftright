#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_ax_value: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Plain").frame(width: 240, height: 20, alignment: .leading)
            Rectangle().fill(Color.red).frame(width: 240, height: 20).accessibilityLabel("Level").accessibilityValue("high")
            Button("Go") { }.accessibilityValue("ready").frame(width: 240, height: 32)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
