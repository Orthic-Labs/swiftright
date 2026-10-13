#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_button_click_prominent: View {
    @State private var n = 0
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) { ForEach(0..<n, id: \.self) { _ in Rectangle().fill(Color.red).frame(width: 8, height: 10) } }.frame(width: 200, height: 10)
            Text("Count \(n)").frame(width: 200, height: 16)
            Button("Add") { n += 1 }.buttonStyle(.borderedProminent)
        }
        .frame(width: 200, height: 120, alignment: .top)
    }
}
