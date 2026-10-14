#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P09b: View {
    let items = ["a", "b", "c"]
    var body: some View { List(items, id: \.self) { Text($0) } }
}
