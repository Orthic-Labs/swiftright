#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P04: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Color.blue, Color.clear], startPoint: .top, endPoint: .bottom))
            .frame(width: 80, height: 40)
    }
}
