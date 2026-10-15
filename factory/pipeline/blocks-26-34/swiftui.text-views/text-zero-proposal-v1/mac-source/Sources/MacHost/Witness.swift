#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_ts_text_zero_proposal: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Color.gray.frame(width: 30, height: 15) }.frame(width: 30, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Color.gray.frame(width: 30, height: 15) }.frame(width: 58, height: 23, alignment: .leading)
            HStack(spacing: 8) { Color.gray.frame(width: 30, height: 15); Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).overlay { Color.red }; Color.gray.frame(width: 30, height: 15) }.frame(width: 38, height: 23, alignment: .leading)
            Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).frame(width: 0, height: 23, alignment: .leading).overlay { Color.red }
            HStack(spacing: 0) { Color.blue.frame(width: 30, height: 23); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).frame(width: 0, height: 23).overlay { Color.red }; Color.green.frame(width: 30, height: 23) }.frame(width: 120, height: 23, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
