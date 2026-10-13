#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_prominent_disabled: View {
    var body: some View {
        Button("Run") {}.buttonStyle(.borderedProminent).disabled(true).frame(width: 100, height: 40)
    }
}
