#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_binding_click: View {
    @State private var count = 3
    var body: some View {
        let derived = Binding<Bool>(get: { count > 0 }, set: { count = $0 ? 1 : 0 })
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Derived", isOn: derived).labelsHidden().toggleStyle(.switch)
            Toggle("Constant", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
            Text("count: \(count)")
        }
    }
}
