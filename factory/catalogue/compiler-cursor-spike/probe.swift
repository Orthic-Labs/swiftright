import SwiftUI
import UniformTypeIdentifiers

struct CursorProbe: View {
    var body: some View {
        VStack {
            Text("x").accessibilityLabel { _ in Text("label") }
            Text("x").sensoryFeedback(trigger: 0) { _, _ in .success }
            Text("x").dropDestination(for: String.self, action: { items, _ -> Bool in !items.isEmpty })
            Text("x").dropDestination(for: String.self, isEnabled: true, action: { _, _ in () })
            Text("x").onDrop(of: [UTType.text], isTargeted: nil) { _ in true }
            Text("x").onDrop(of: [UTType.text], isTargeted: nil) { _, _ in true }
        }
    }
}
