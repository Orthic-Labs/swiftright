#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_list_five: View {
    
    var body: some View {
        List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)") } }.frame(width: 200, height: 160)
    }
}
