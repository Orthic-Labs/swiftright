#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P19: View {
    var body: some View {
        VStack {
            HStack { Text("a"); Spacer(); Text("b") }
            Divider()
            Spacer()
        }
    }
}
