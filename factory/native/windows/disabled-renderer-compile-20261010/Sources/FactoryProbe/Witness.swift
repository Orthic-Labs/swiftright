#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_disabled: View {
    var body: some View {
        Button("Continue") {}.disabled(true)
            .environment(\.colorScheme, .light)
    }
}
