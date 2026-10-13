#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_image_baseline: View {
    var body: some View {
        Image(systemName: "star.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .foregroundStyle(.yellow)
            .environment(\.colorScheme, .light)
    }
}
