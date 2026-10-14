#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P10: View {
    @State private var sel: String? = "a"
    var body: some View {
        NavigationSplitView {
            List(selection: $sel) { ForEach(["a", "b"], id: \.self) { Text($0) } }
        } detail: {
            Text(sel ?? "none")
        }
    }
}
