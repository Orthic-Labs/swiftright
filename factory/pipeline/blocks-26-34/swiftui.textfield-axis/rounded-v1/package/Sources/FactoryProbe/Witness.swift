#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tfa_rounded: View {
    @State private var name = ""
    var body: some View { TextField("Name", text: $name, axis: .vertical).textFieldStyle(.roundedBorder).frame(width: 120).padding(10) }
}
