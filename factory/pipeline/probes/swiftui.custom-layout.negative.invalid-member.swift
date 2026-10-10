#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_swiftui_custom_layout_negative_invalid_member: View {
    var body: some View { Text("invalid").swiftRightDefinitelyMissingMember() }
}
