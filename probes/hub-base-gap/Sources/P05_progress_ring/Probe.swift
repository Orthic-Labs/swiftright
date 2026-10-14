#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P05: View {
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 60, height: 60)
    }
}
