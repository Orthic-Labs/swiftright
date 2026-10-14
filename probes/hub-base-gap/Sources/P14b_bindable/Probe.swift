#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

@Observable final class P14bModel { var name = "" }
struct P14b: View {
    @State private var m = P14bModel()
    var body: some View {
        @Bindable var b = m
        return TextField("Name", text: $b.name)
    }
}
