#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P21: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow { Text("a"); Text("b") }
            GridRow { Text("c"); Text("d") }
        }
    }
}
