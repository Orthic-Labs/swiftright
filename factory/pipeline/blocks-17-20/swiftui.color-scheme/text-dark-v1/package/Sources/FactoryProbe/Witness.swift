#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_cs_text_dark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(alignment: .leading, spacing: 0) {
                Text("MMMMMMMM").frame(height: 24, alignment: .topLeading)
                Text("MMMMMMMM").frame(height: 24, alignment: .topLeading).foregroundStyle(.secondary)
                Text("MMMMMMMM").frame(height: 24, alignment: .topLeading).foregroundStyle(Color.accentColor)
                Text("MMMMMMMM").frame(height: 24, alignment: .topLeading).foregroundStyle(Color.red)
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
        .environment(\.colorScheme, .dark)
    }
}
