#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P22: View {
    var body: some View {
        VStack {
            Color.red.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            Color.blue.frame(width: 40, height: 40).clipShape(Circle())
        }
    }
}
