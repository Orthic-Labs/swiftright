#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_imet_imetfocuschangev1: View {
    @State private var a = "ab"
    @State private var b = "xy"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("First", text: $a).textFieldStyle(.roundedBorder)
            TextField("Second", text: $b).textFieldStyle(.roundedBorder)
            Text("bound: \(a) | \(b)")
        }.frame(width: 120).padding(10)
    }
}
