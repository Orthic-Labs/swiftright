#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_list_variable: View {
    
    var body: some View {
        List {
            Rectangle().fill(Color.red).frame(width: 32, height: 12)
            Rectangle().fill(Color.red).frame(width: 30, height: 40)
            Rectangle().fill(Color.red).frame(width: 30, height: 24)
        }.frame(width: 200, height: 160)
    }
}
