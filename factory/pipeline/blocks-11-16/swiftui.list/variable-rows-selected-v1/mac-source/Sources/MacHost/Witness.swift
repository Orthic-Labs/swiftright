#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_list_variable_selected: View {
    @State private var sel: Int? = nil
    var body: some View {
        List(selection: $sel) {
            Rectangle().fill(Color.red).frame(width: 32, height: 12).tag(0)
            Rectangle().fill(Color.red).frame(width: 30, height: 40).tag(1)
            Rectangle().fill(Color.red).frame(width: 30, height: 24).tag(2)
        }.frame(width: 200, height: 160)
    }
}
