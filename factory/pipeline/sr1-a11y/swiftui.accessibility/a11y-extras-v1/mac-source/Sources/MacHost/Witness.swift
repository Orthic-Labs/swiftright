#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import CoreGraphics
#endif

// ABI 0.13 accessibility extras (#60), case a11y-extras-v1: a header, a button with a hint, a value, a link and a plain Text. The witness is byte-identical on both
// platforms; the semantic gate compares role, name, help, heading and link of the UIA tree (Windows) with the AX tree (Mac).
struct Witness_a11y_extras_v1: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Title").accessibilityAddTraits(.isHeader)
            Button("Save") {}.accessibilityHint("Saves the file")
            Text("42").accessibilityValue("forty-two")
            Text("Docs").accessibilityAddTraits(.isLink)
            Text("Plain")
        }.frame(width: 200, height: 200)
    }
}
