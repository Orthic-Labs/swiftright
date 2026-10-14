#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P06: View {
    var body: some View {
        VStack {
            ProgressView(value: 0.4)
            ProgressView("Loading", value: 0.5, total: 1)
            ProgressView()
        }
    }
}
