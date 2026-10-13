#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_alert_confirm_escape: View {
    @State private var show = true
    @State private var done = false
    var body: some View {
        VStack(spacing: 8) {
            Rectangle().fill(done ? Color.green : Color.red).frame(width: 80, height: 40)
            Text(done ? "Done" : "Waiting")
        }
        .frame(width: 320, height: 240)
        .confirmationDialog("Delete item?", isPresented: $show, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { done = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
    }
}
