#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P11: View {
    var body: some View {
        NavigationStack {
            NavigationLink("Open") { Text("Detail") }
                .navigationTitle("Home")
        }
    }
}
