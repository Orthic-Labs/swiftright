#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

@Observable final class P14Model { var count = 0 }
struct P14: View {
    @State private var m = P14Model()
    var body: some View { Button("n=\(m.count)") { m.count += 1 } }
}
