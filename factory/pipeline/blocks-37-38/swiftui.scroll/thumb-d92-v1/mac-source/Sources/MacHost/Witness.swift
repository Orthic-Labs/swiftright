#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sc_thumb_d92: View {
    var body: some View {
        List { ForEach(0..<3, id: \.self) { i in Text("Row \(i)") } }.frame(width: 180, height: 90)
    }
}
