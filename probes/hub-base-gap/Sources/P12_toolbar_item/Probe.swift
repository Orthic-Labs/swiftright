#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P12: View {
    var body: some View {
        NavigationStack {
            Text("x")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Button("Add") {} }
                }
        }
    }
}
