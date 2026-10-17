#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sc_wheel_sv_d92: View {
    var body: some View {
        ScrollView { VStack(spacing: 0) { ForEach(0..<3, id: \.self) { i in Text("Row \(i)").frame(width: 160, height: 24) } } }.frame(width: 180, height: 90)
    }
}
