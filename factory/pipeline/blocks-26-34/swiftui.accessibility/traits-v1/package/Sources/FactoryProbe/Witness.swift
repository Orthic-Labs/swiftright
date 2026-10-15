#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_ax_traits: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Static text").accessibilityAddTraits(.isStaticText).frame(width: 240, height: 20, alignment: .leading)
            Rectangle().fill(Color.blue).frame(width: 240, height: 20).accessibilityLabel("Chart").accessibilityAddTraits(.isImage)
            Button("Selected") { }.accessibilityAddTraits(.isSelected).frame(width: 240, height: 32)
            Button("Chosen") { }.accessibilityAddTraits([.isSelected, .isButton]).frame(width: 240, height: 32)
            Text("Live text").accessibilityAddTraits(.updatesFrequently).frame(width: 240, height: 20, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
