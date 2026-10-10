#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_padding_frame: View {
    var body: some View {
        Text("Box").padding(4).frame(width: 96, height: 40, alignment: .center)
    }
}
