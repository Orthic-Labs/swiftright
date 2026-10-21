#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

// Issue #61, emoji-text-v1: colour emoji Text. Glyph shapes differ by design (Segoe UI Emoji COLR on Windows through gpui paint_emoji, G16, against Apple Color Emoji):
// the glyph regions are excluded and gated by size and position through the frames only; every pixel outside them is exact.
struct Witness_i61_emoji_text_v1: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\u{1F600}").font(.system(size: 32)).frame(width: 64, height: 48, alignment: .leading).accessibilityElement(children: .ignore).accessibilityLabel("Emoji large")
            Text("A\u{1F600}B").font(.system(size: 17)).frame(width: 120, height: 48, alignment: .leading).accessibilityElement(children: .ignore).accessibilityLabel("Emoji in Latin line")
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
