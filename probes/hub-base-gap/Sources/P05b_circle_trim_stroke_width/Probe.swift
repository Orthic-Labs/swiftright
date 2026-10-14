#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P05b: View {
    var body: some View { Circle().trim(from: 0, to: 0.7).stroke(Color.green, lineWidth: 6).frame(width: 60, height: 60) }
}
