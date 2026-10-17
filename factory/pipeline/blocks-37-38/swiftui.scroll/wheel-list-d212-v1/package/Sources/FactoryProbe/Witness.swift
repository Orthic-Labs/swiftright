#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sc_wheel_list_d212: View {
    var body: some View {
        List { ForEach(0..<8, id: \.self) { i in Text("Row \(i)") } }.frame(width: 180, height: 90)
    }
}
