#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_padding_frame: View {
    var body: some View {
        Text("Box").padding(12).frame(width: 72, height: 40, alignment: .trailing)
    }
}
