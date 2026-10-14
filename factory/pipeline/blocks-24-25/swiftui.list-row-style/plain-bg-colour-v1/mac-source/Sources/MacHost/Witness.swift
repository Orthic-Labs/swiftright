#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_lrs_plain_bg_colour: View {
    
    var body: some View {
        List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").listRowBackground(Color.green) } }.listStyle(.plain).frame(width: 200, height: 160)
    }
}
