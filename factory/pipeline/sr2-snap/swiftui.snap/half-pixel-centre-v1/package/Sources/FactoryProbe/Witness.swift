#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

// Issue #44 probe: frames centred on a half device pixel at scale 2.5 (an odd number of half points of slack), unscaled. Row 1: a 30 pt rect in an 80 pt
// frame (origin 25 pt = 62.5 px); row 2: a 31 pt rect (24.5 pt = 61.25 px); row 3: a 30 pt circle. The Mac capture gives SwiftUI's window snapping rule.
struct Witness_snap_half_pixel_centre_v1: View {
    var body: some View {
        VStack(spacing: 4) {
            Color.red.frame(width: 30, height: 30).frame(width: 80, height: 36)
            Color.green.frame(width: 31, height: 31).frame(width: 80, height: 36)
            Circle().fill(Color.blue).frame(width: 30, height: 30).frame(width: 80, height: 36)
        }
        .frame(width: 240, height: 160)
    }
}
