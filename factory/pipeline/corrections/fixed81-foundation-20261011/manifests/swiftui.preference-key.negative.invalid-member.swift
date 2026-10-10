#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

import Foundation

struct Witness_swiftui_preference_key_negative_invalid_member: View {
    var body: some View { Text("invalid").swiftRightDefinitelyMissingMember() }
}
