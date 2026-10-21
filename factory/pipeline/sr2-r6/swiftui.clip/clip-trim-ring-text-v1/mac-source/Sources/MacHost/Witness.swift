#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

private let blue = Color(.sRGB, red: 0.2, green: 0.6, blue: 1.0, opacity: 1)
private let orange = Color(.sRGB, red: 1.0, green: 0.4, blue: 0.2, opacity: 1)

// Issue #52 pass 2, case clip-trim-ring-text-v1: a trimmed Circle ring stroke (lineWidth 6, trim 0..0.7, round caps) beside a Text that is wider than the
// 90 pt Circle clip it sits in, so the clip's path cuts the glyph run (renderer path fill/stroke and path clip, ABI 0.12).
struct Witness_r6_clip_trim_ring_text_v1: View {
    var body: some View {
        HStack(spacing: 20) {
            Circle().inset(by: 3).trim(from: 0, to: 0.7)
                .stroke(blue, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 80, height: 80)
            ZStack {
                orange
                Text("0123456789").font(Font.system(size: 22, weight: .semibold)).foregroundColor(.white).fixedSize()
            }
            .frame(width: 90, height: 90)
            .clipShape(Circle())
        }
    }
}
