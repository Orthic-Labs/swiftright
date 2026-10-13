#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_round2_environment: View {
    var body: some View {
        VStack { Text("Inherited environment"); Text("Inherited child") }
            .environment(\.font, .system(size: 24))
            .environment(\.colorScheme, .dark)
    }
}
