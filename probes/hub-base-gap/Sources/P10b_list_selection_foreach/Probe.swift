#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P10b: View {
    @State private var sel: String? = "a"
    var body: some View {
        List(selection: $sel) { ForEach(["a", "b"], id: \.self) { Text($0).tag($0) } }
    }
}
