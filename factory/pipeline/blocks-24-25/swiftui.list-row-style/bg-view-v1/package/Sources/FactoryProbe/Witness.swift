#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_lrs_bg_view: View {
    
    var body: some View {
        List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").listRowBackground(Rectangle().fill(Color.blue)) } }.frame(width: 200, height: 160)
    }
}
