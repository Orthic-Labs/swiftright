#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P15: View {
    @State private var on = true
    var body: some View {
        Form {
            Section("General") { Toggle("Enabled", isOn: $on) }
            Section(header: Text("More")) { Text("x") }
        }
    }
}
