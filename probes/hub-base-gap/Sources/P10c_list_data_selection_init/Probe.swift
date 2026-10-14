#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P10c: View {
    @State private var sel: String? = "a"
    let items = ["a", "b"]
    var body: some View { List(items, id: \.self, selection: $sel) { Text($0) } }
}
