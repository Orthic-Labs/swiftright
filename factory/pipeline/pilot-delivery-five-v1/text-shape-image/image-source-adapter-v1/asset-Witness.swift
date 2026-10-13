#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_image_asset: View {
    var body: some View {
        Image("sr1.rgba.checker")
            .resizable()
            .scaledToFit()
            .frame(width: 32, height: 32)
            .environment(\.colorScheme, .light)
    }
}
