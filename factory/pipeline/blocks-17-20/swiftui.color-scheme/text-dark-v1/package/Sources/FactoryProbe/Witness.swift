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
                Text("MMMM").font(.system(size: 36, weight: .bold)).frame(height: 48, alignment: .topLeading)
                Text("MMMM").font(.system(size: 36, weight: .bold)).frame(height: 48, alignment: .topLeading).foregroundStyle(.secondary)
                Text("MMMM").font(.system(size: 36, weight: .bold)).frame(height: 48, alignment: .topLeading).foregroundStyle(Color.accentColor)
                Text("MMMM").font(.system(size: 36, weight: .bold)).frame(height: 48, alignment: .topLeading).foregroundStyle(Color.red)
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
        .environment(\.colorScheme, .dark)
    }
}
