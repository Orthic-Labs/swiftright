#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_uia_a: View {
    @State private var on = true
    @State private var off = false
    @State private var text = "Hello"
    @State private var v = 40.0
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Title")
            HStack(spacing: 8) { Button("Add") { }; Button("Plain") { }.buttonStyle(.plain); Button("Off") { }.disabled(true) }
            Toggle("Switch", isOn: $on).toggleStyle(.switch)
            Toggle("Check", isOn: $off)
            TextField("Name", text: $text).frame(width: 160)
            Slider(value: $v, in: 0...100).frame(width: 160)
            Divider().frame(width: 160)
            Toggle("Disabled", isOn: $on).toggleStyle(.switch).disabled(true)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
