#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P09: View {
    @State private var q = ""
    var body: some View {
        List { ForEach(["a", "b", "c"], id: \.self) { Text($0) } }
            .searchable(text: $q)
    }
}
