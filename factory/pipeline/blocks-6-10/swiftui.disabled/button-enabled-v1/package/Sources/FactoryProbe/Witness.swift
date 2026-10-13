#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_enabled: View {
    var body: some View {
        Button("Run") {}.frame(width: 100, height: 40)
    }
}
