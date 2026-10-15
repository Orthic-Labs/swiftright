#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_tfa_plain: View {
    @State private var name = ""
    var body: some View { TextField("Name", text: $name, axis: .vertical).textFieldStyle(.plain).frame(width: 120).padding(10) }
}
