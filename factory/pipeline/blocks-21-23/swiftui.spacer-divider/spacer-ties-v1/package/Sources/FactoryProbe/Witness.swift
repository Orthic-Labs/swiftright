#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif

struct Witness_sd_spacer_ties: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 3, height: 10); Spacer().frame(width: 5); Rectangle().fill(Color.blue).frame(width: 7, height: 10); Spacer(minLength: 9); Rectangle().fill(Color.red).frame(width: 1, height: 10); Spacer().frame(width: 27); Rectangle().fill(Color.blue).frame(width: 11, height: 10) }.frame(width: 200, alignment: .leading)
            Spacer().frame(height: 5)
            HStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 5, height: 10); Spacer(); Rectangle().fill(Color.blue).frame(width: 9, height: 10); Spacer().frame(width: 13); Rectangle().fill(Color.red).frame(width: 3, height: 10) }.frame(width: 111, alignment: .leading)
            Spacer().frame(height: 7)
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) { Rectangle().fill(Color.red).frame(width: 10, height: 3); Spacer().frame(height: 5); Rectangle().fill(Color.blue).frame(width: 10, height: 7); Spacer(minLength: 9); Rectangle().fill(Color.red).frame(width: 10, height: 1) }
                Spacer().frame(width: 7)
                VStack(spacing: 0) { Rectangle().fill(Color.blue).frame(width: 10, height: 27); Spacer(); Rectangle().fill(Color.red).frame(width: 10, height: 11) }.frame(height: 71)
            }
        }
    }
}
