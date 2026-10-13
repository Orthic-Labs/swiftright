#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_cs_probe: View {
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Rectangle().fill(scheme == .dark ? Color.red : Color.blue).frame(width: 40, height: 20)
    }
}

struct Witness_cs_preferred_dark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(alignment: .leading, spacing: 4) {
                Witness_cs_probe()
                Rectangle().fill(.primary).frame(width: 40, height: 20)
                Rectangle().fill(Color.accentColor).frame(width: 40, height: 20)
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
        .preferredColorScheme(.dark)
    }
}
