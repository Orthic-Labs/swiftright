// SR0-C negative fixture. Not part of `swift build`; compiled separately with swiftc -typecheck.
// Uses NavigationSplitView, which is NOT in the SR0-C stub inventory.
// Expected: macOS compiles (real SwiftUI); Windows reports an unknown-symbol error.
#if os(macOS)
import SwiftUI
#endif
import SwiftRightUI

struct NegativeNavigationScreen: View {
    var body: some View {
        NavigationSplitView {
            Text("Sidebar")
        } detail: {
            Text("Detail")
        }
    }
}
