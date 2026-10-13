#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_text_colour: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Red").foregroundColor(Color.red)
            Text("Grey").foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.5))
            Text("Plain")
        }
        .frame(width: 160, height: 120)
    }
}
