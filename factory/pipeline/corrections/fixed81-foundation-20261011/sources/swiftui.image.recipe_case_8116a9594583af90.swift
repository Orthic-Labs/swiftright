#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_image: View {
    var body: some View {
        Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 32, height: 32)
            .foregroundStyle(.yellow)
            .environment(\.displayScale, 2)
            .environment(\.colorScheme, .dark)
    }
}
