#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_bd_states: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.background)
            VStack(spacing: 6) {
                Button("Bordered") { }.frame(width: 120, height: 24)
                Button("Disabled") { }.disabled(true).frame(width: 120, height: 24)
                Button("Prominent") { }.buttonStyle(.borderedProminent).frame(width: 120, height: 24)
                Button("Prominent off") { }.buttonStyle(.borderedProminent).disabled(true).frame(width: 120, height: 24)
                Button("Default") { }.keyboardShortcut(.defaultAction).frame(width: 120, height: 24)
                Button("Borderless") { }.buttonStyle(.borderless).frame(width: 120, height: 24)
                Button("Plain") { }.buttonStyle(.plain).frame(width: 120, height: 24)
            }.padding(.top, 16)
        }
        .frame(width: 320, height: 240).environment(\.colorScheme, .dark)
    }
}
