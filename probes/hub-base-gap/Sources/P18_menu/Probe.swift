#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P18: View {
    var body: some View {
        Menu("Actions") {
            Button("One") {}
            Divider()
            Button("Two") {}
        }
    }
}
