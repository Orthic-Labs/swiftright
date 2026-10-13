#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_prominent: View {
    var body: some View {
        Button("Run") {}.buttonStyle(.borderedProminent).frame(width: 100, height: 40)
    }
}
