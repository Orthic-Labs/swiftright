#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P16: View {
    @State private var s = "a"
    var body: some View {
        Picker("Mode", selection: $s) {
            Text("A").tag("a")
            Text("B").tag("b")
        }
    }
}
