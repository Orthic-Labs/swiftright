#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sc_scroller_list: View {
    var body: some View {
        List { ForEach(0..<25, id: \.self) { i in Text("Row \(i)") } }.frame(width: 180, height: 90)
    }
}
