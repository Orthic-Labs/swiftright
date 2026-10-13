#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_binding_derived: View {
    @State private var count = 3
    @State private var flag = false
    var body: some View {
        let derived = Binding<Bool>(get: { count > 0 }, set: { count = $0 ? 1 : 0 })
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Derived", isOn: derived).labelsHidden().toggleStyle(.switch)
            Toggle("Projected", isOn: $flag).labelsHidden().toggleStyle(.switch)
            HStack(spacing: 8) {
                Rectangle().fill(count == 3 ? Color.green : Color.red).frame(width: 20, height: 20)
                Text("count: \(count)").frame(height: 20, alignment: .topLeading)
            }
        }
    }
}
