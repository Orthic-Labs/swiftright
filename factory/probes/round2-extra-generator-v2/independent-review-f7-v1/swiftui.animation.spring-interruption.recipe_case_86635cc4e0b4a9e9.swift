#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_round2_spring: View {
    @State private var expanded = false
    var body: some View {
        VStack {
            Button("Interrupt spring") {
                withAnimation(.spring) {
                    expanded.toggle()
                }
            }
            Rectangle().frame(width: 40, height: 40).offset(x: expanded ? 80 : 0)
        }
    }
}
