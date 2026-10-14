#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P23: View {
    var body: some View { Text("x").offset(x: 4, y: 2) }
}
