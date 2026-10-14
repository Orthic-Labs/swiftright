#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P05c: View {
    var body: some View { Rectangle().fill(Color.green).frame(width: 40, height: 10).rotationEffect(.degrees(-90)) }
}
