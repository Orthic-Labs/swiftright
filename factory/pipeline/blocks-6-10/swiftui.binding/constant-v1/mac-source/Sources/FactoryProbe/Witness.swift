#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_binding_constant: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("On", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
            Toggle("Off", isOn: .constant(false)).labelsHidden().toggleStyle(.switch)
        }
    }
}
