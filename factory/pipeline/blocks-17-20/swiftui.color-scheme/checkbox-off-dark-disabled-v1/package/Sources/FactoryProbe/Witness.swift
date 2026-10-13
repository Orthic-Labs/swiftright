#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_cs_checkbox_off_dark_disabled: View {
    @State private var enabled = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            Toggle("Enabled", isOn: $enabled).labelsHidden().toggleStyle(.automatic).disabled(true)
        }
        .frame(width: 320, height: 240)
        .environment(\.colorScheme, .dark)
    }
}
