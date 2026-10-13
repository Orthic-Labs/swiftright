#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_alert_focus: View {
    @State private var name = "ab"
    @State private var show = false
    @State private var done = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name", text: $name).focused($focused)
            Text(focused ? "focus: field" : "focus: none")
            Text(done ? "Done" : "Waiting")
        }
        .frame(width: 200)
        .padding(10)
        .onAppear { focused = true; show = true }
        .alert("Save?", isPresented: $show) {
            Button("OK") { done = true }
        } message: {
            Text("Your name will be saved.")
        }
    }
}
