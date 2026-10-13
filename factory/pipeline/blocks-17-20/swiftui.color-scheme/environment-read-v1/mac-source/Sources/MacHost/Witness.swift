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

struct Witness_cs_env_read: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(alignment: .leading, spacing: 4) {
                Witness_cs_probe()
                Witness_cs_probe().environment(\.colorScheme, .dark)
                Witness_cs_probe().environment(\.colorScheme, .dark).environment(\.colorScheme, .light)
                VStack(alignment: .leading, spacing: 2) { Witness_cs_probe(); Witness_cs_probe().environment(\.colorScheme, .light) }.environment(\.colorScheme, .dark)
                HStack(spacing: 4) { Witness_cs_probe(); Witness_cs_probe().environment(\.colorScheme, .dark) }
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
    }
}
