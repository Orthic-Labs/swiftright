#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

/// Explicit source-bound RGBA image block. It does not claim SF Symbol identity.
struct Witness_image_rgba: View {
    var body: some View {
        Image("factory.rgba.square.v1")
            .resizable(resizingMode: .stretch)
            .scaledToFit()
            .frame(width: 32, height: 32)
            .environment(\.colorScheme, .light)
    }
}
