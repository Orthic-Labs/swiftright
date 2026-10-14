#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P24: View {
    var body: some View {
        VStack {
            Circle().frame(width: 20, height: 20).scaleEffect(1.2)
            Circle().frame(width: 20, height: 20).scaleEffect(x: 1.1, y: 0.9, anchor: .topLeading)
        }
    }
}
