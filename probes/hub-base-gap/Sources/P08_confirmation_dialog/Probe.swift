#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P08: View {
    @State private var show = false
    var body: some View {
        Button("Delete") { show = true }
            .confirmationDialog("Delete?", isPresented: $show, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
    }
}
