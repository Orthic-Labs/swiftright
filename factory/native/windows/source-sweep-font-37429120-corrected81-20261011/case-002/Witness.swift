#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

import Foundation

struct Witness_swiftui_custom_layout_negative_invalid_member: View {
    var body: some View { Text("invalid").swiftRightDefinitelyMissingMember() }
}
