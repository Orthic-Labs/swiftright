#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P25: View {
    var body: some View {
        Text("x").padding(4).background(RoundedRectangle(cornerRadius: 4).fill(Color.blue))
    }
}
