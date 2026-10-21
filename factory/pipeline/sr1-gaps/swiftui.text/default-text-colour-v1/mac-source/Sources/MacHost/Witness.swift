#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

// Issue #63, case default-text-colour-v1: plain Text with no foreground style set (Windows default 0x1f1f1f against the Mac's 0x272727).
struct Witness_g63_default_text_colour_v1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Default colour text")
            Text("Second line, no foreground")
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
