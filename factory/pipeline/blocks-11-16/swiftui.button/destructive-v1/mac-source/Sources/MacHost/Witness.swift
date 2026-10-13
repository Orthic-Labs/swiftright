#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_destructive: View {
    var body: some View {
        Button("Run", role: .destructive) {}.frame(width: 100, height: 40)
    }
}
