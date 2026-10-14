#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P17: View {
    @State private var v = 0.5
    var body: some View { Slider(value: $v, in: 0...1) }
}
