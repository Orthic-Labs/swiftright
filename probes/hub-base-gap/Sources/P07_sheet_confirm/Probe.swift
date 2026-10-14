#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

struct P07: View {
    @State private var show = false
    var body: some View {
        Button("Delete") { show = true }
            .sheet(isPresented: $show) {
                VStack {
                    Text("Are you sure?")
                    Button("OK") { show = false }
                }
            }
    }
}
