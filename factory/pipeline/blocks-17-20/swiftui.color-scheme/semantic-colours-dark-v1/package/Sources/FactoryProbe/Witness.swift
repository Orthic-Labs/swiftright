#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_cs_semantic_dark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Rectangle().fill(.primary).frame(width: 40, height: 20)
                    Rectangle().fill(.secondary).frame(width: 40, height: 20)
                    Rectangle().fill(Color.accentColor).frame(width: 40, height: 20)
                    ZStack { Rectangle().fill(Color.red); Rectangle().fill(.background).frame(width: 24, height: 12) }.frame(width: 40, height: 20)
                }
                HStack(spacing: 4) {
                    Rectangle().fill(Color.red).frame(width: 24, height: 20)
                    Rectangle().fill(Color.orange).frame(width: 24, height: 20)
                    Rectangle().fill(Color.yellow).frame(width: 24, height: 20)
                    Rectangle().fill(Color.green).frame(width: 24, height: 20)
                    Rectangle().fill(Color.blue).frame(width: 24, height: 20)
                    Rectangle().fill(Color.purple).frame(width: 24, height: 20)
                    Rectangle().fill(Color.pink).frame(width: 24, height: 20)
                    Rectangle().fill(Color.gray).frame(width: 24, height: 20)
                }
                HStack(spacing: 4) {
                    Rectangle().fill(Color.white).frame(width: 40, height: 20)
                    Rectangle().fill(Color.black).frame(width: 40, height: 20)
                }
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
        .environment(\.colorScheme, .dark)
    }
}
