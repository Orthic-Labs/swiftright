#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_disabled: View {
    var body: some View {
        Button("Run") {}.frame(width: 100, height: 40).disabled(true)
    }
}
