#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_cs_switch_on_dark: View {
    @State private var enabled = true
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            Toggle("Enabled", isOn: $enabled).labelsHidden().toggleStyle(.switch)
        }
        .frame(width: 320, height: 240)
        .environment(\.colorScheme, .dark)
    }
}
