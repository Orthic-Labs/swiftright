#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sc_keys_sv: View {
    var body: some View {
        ScrollView { VStack(spacing: 0) { ForEach(0..<25, id: \.self) { i in Text("Row \(i)").frame(width: 160, height: 24) } } }.frame(width: 180, height: 90)
    }
}
