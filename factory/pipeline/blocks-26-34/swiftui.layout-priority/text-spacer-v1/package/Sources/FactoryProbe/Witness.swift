#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif

struct Witness_ts_text_spacer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Spacer(); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue } }.frame(width: 170, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Spacer(); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue } }.frame(width: 200, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Spacer(); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue } }.frame(width: 240, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }.layoutPriority(1); Spacer(); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue } }.frame(width: 150, height: 23, alignment: .leading)
            HStack(spacing: 8) { Spacer(); Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red } }.frame(width: 80, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Spacer(minLength: 30); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue } }.frame(width: 200, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Spacer(); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue }.layoutPriority(1) }.frame(width: 130, height: 23, alignment: .leading)
            HStack(spacing: 8) { Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.red }; Spacer(); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.blue }; Spacer(); Text("Hi").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).overlay { Color.green } }.frame(width: 150, height: 23, alignment: .leading)
        }.frame(width: 240, height: 200, alignment: .topLeading)
    }
}
