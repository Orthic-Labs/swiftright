#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P27: View {
    @State private var hot = false
    var body: some View {
        Text(hot ? "hot" : "cold").onHover { hot = $0 }
    }
}
