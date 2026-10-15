#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_bd_states_disabled: View {
    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.background)
            VStack(spacing: 6) {
                Button("Borderless") { }.buttonStyle(.borderless).disabled(true).frame(width: 120, height: 24)
                Button("Plain") { }.buttonStyle(.plain).disabled(true).frame(width: 120, height: 24)
                Button("Red") { }.buttonStyle(.borderless).foregroundStyle(Color.red).frame(width: 120, height: 24)
                Button("Red plain") { }.buttonStyle(.plain).foregroundStyle(Color.red).frame(width: 120, height: 24)
            }.padding(.top, 16)
        }
        .frame(width: 320, height: 240).environment(\.colorScheme, .dark)
    }
}
