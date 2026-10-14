#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P20: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) { ForEach(0..<20, id: \.self) { Text("\($0)") } }
        }
    }
}
