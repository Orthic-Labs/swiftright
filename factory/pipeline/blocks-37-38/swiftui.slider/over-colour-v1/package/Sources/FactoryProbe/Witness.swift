#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_sl_over_colour: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack { Color(red: 0.2, green: 0.4, blue: 0.8); Slider(value: .constant(40), in: 0...100).frame(width: 200) }.frame(width: 240, height: 48)
            ZStack { Color(red: 0.5, green: 0.5, blue: 0.5); Slider(value: .constant(60), in: 0...100).frame(width: 200) }.frame(width: 240, height: 48)
            ZStack { Color.black; Slider(value: .constant(80), in: 0...100).frame(width: 200) }.frame(width: 240, height: 48)
            ZStack { Color(red: 0.9, green: 0.8, blue: 0.3); Slider(value: .constant(20), in: 0...100).frame(width: 200).disabled(true) }.frame(width: 240, height: 48)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
