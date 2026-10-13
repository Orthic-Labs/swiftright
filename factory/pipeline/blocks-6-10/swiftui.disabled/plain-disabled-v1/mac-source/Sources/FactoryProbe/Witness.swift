#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_disabled_plain: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Plain")
            RoundedRectangle(cornerRadius: 8).fill(Color.blue).frame(width: 80, height: 30)
            Circle().fill(Color.red).frame(width: 30, height: 30)
        }
        .frame(width: 160, height: 120)
        .disabled(true)
    }
}
