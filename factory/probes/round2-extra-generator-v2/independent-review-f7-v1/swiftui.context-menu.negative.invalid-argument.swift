#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Negative_round2: View {
    var body: some View { Text("Menu").contextMenu { 17 } }
}
