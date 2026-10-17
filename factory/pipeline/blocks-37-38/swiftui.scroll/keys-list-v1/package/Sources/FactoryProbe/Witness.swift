#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sc_keys_list: View {
    @State private var sel: Int? = nil
    var body: some View {
        List(selection: $sel) { ForEach(0..<25, id: \.self) { i in Text("Row \(i)") } }.frame(width: 180, height: 90)
    }
}
