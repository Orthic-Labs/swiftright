#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_swiftui_text_bundled_font_negative_invalid_member: View {
    var body: some View { Text("invalid").swiftRightDefinitelyMissingMember() }
}
